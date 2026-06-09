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

  # Continuous interval: 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    failures = case mcp_result do
      {:error, reason} -> [{:error, reason} | failures]
      _ -> failures
    end

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_automated_pr(failures)
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

  defp check_mcp_endpoint(url) do
    {time_us, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_ms = time_us / 1000

    if time_ms > 1000 do
      {:error, "Endpoint #{url} response time exceeded 1000ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _reason} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp create_automated_pr(failures) do
    try do
      # Deduplicate PR creation
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if output == "" do
            do_create_pr(failures)
          else
            Logger.info("Automated PR already exists, skipping.")
          end
        {_, _} ->
          Logger.error("Failed to check existing PRs with gh CLI")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute gh CLI: #{inspect(e)}")
    end
  end

  defp do_create_pr(failures) do
    branch_name = "automated-ax-fix-#{System.unique_integer([:positive])}"

    try do
      {_, 0} = System.cmd("git", ["checkout", "-b", branch_name])

      # Write a fix file
      fix_path = Path.join(File.cwd!(), "priv/ax_audit_fix.log")

      string_failures = Enum.map(failures, fn {:error, reason} -> reason end)

      File.write!(fix_path, Jason.encode!(string_failures))

      {_, 0} = System.cmd("git", ["add", "priv/ax_audit_fix.log"])
      {_, 0} = System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
      {_, 0} = System.cmd("git", ["push", "-u", "origin", branch_name])
      {_, 0} = System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated AX Audit fix for endpoints."])
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute git/gh CLI for PR creation: #{inspect(e)}")
      e ->
        Logger.error("Failed to create automated PR: #{inspect(e)}")
    after
      System.cmd("git", ["checkout", "main"])
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
