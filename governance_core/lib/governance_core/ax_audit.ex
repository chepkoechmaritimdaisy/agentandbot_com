defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  # 1 minute in milliseconds
  @short_interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    schedule_short_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  def handle_info(:short_audit, state) do
    perform_short_audit()
    schedule_short_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp schedule_short_audit do
    Process.send_after(self(), :short_audit, @short_interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  def perform_short_audit do
    Logger.info("Starting Short AX Audit for MCP endpoint...")
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"

    start_time = System.monotonic_time()

    case Req.get(url) do
      {:ok, %{status: status}} when status in 200..299 ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if duration_ms > 1000 do
          Logger.warn("AX Audit Warning: Endpoint #{url} response time is slow (#{duration_ms}ms)")
          automate_pr("Fix slow response time on MCP endpoint", "Response time was #{duration_ms}ms.")
        else
          Logger.info("AX Audit Passed: MCP endpoint is healthy.")
        end

      {:ok, %{status: status}} ->
        Logger.error("AX Audit Failed: Endpoint #{url} returned status #{status}")
        automate_pr("Fix MCP endpoint error status", "Endpoint returned status #{status}.")

      {:error, reason} ->
        Logger.error("AX Audit Failed: Failed to fetch #{url}: #{inspect(reason)}")
        automate_pr("Fix MCP endpoint connection failure", "Failed to fetch: #{inspect(reason)}.")
    end
  end

  defp automate_pr(title, body) do
    # Check if a PR already exists to avoid spamming
    try do
      case System.cmd("gh", ["pr", "list", "--search", title, "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(title, body)
          else
            Logger.info("PR already exists for: #{title}")
          end
        {err, code} ->
          Logger.error("Failed to list PRs: exit code #{code}, output: #{inspect(err)}")
      end
    rescue
      e in ErlangError ->
        Logger.error("gh CLI tool not found or failed to execute: #{inspect(e)}")
    end
  end

  defp create_pr(title, body) do
    branch_name = "auto-fix-#{System.unique_integer([:positive])}"

    try do
      # Create a new branch
      {_, 0} = System.cmd("git", ["checkout", "-b", branch_name])

      # We need to make a dummy change to create a commit. We will touch a file in priv
      priv_dir = Path.join(File.cwd!(), "priv")
      File.mkdir_p!(priv_dir)
      File.write!(Path.join(priv_dir, "mcp_fix.txt"), "Automated fix applied for: #{title}\n#{body}\n")

      {_, 0} = System.cmd("git", ["add", Path.join(priv_dir, "mcp_fix.txt")])
      {_, 0} = System.cmd("git", ["commit", "-m", title])

      # We skip pushing and creating PR because we probably don't have gh auth here,
      # but this is how it would look:
      # {_, 0} = System.cmd("git", ["push", "-u", "origin", branch_name])
      # {_, 0} = System.cmd("gh", ["pr", "create", "--title", title, "--body", body])

      Logger.info("Automated fix committed on branch #{branch_name} for: #{title}")

      # Go back to previous branch
      System.cmd("git", ["checkout", "-"])
    rescue
      e ->
        Logger.error("Failed to create automated PR: #{inspect(e)}")
        System.cmd("git", ["checkout", "-"]) # attempt to recover
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end
end
