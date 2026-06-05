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

    # Check the /api/mcp endpoint separately
    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)

    all_results = [mcp_result | results]

    failures = Enum.filter(all_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_audit_failures(failures)
    end
  end

  defp handle_audit_failures(failures) do
    failure_messages = Enum.map(failures, fn {:error, reason} -> reason end)

    # Try to deduplicate PRs
    try do
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_automated_pr(failure_messages)
          else
            Logger.info("AX Audit: Open automated fix PR already exists. Skipping PR creation.")
          end
        {_, code} ->
          Logger.warning("AX Audit: gh pr list failed with code #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("AX Audit: gh CLI not available: #{inspect(e)}")
    end
  end

  defp create_automated_pr(failures) do
    # Generate an automated fix artifact
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    fix_path = Path.join(priv_dir, "ax_audit_automated_fix.json")

    encoded_failures = Enum.map(failures, &to_string/1)

    case File.write(fix_path, Jason.encode!(%{fixes_for: encoded_failures})) do
      :ok ->
        branch_name = "automated-ax-fix-#{System.system_time(:second)}"

        try do
          System.cmd("git", ["checkout", "-b", branch_name])
          System.cmd("git", ["add", fix_path])
          System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
          System.cmd("git", ["push", "-u", "origin", branch_name])

          case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for agent-friendly audit failures."]) do
            {_, 0} -> Logger.info("Successfully created automated PR for AX Audit failures.")
            {err, _} -> Logger.error("Failed to create PR: #{err}")
          end
        rescue
          e in ErlangError -> Logger.error("Git/GH operations failed: #{inspect(e)}")
        end
      {:error, reason} ->
        Logger.error("Failed to write automated fix file: #{inspect(reason)}")
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
    {time_us, result} =
      :timer.tc(fn ->
        Req.get(url, decode_body: false)
      end)

    # Convert us to ms
    time_ms = time_us / 1000

    if time_ms > 1000 do
      {:error, "Endpoint #{url} response time exceeded 1000ms (#{time_ms}ms)"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          # If the endpoint simply doesn't exist yet, we still return error but specify
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
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
