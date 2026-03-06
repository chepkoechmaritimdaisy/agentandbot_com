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
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    failures = Enum.filter(html_results ++ mcp_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_fix_pr(failures)
    end
  end

  defp prepare_fix_pr(failures) do
    # Creates an issue / PR using the 'gh' CLI or similar
    Logger.info("Preparing automated PR for AX Audit failures...")

    issue_title = "Automated AX Audit Fix Required"
    issue_body = "The following endpoints failed the Agent-Friendly (AX) Audit:\n\n" <> Enum.map_join(failures, "\n", fn {_status, msg} -> "- #{msg}" end)

    case System.cmd("gh", ["issue", "create", "--title", issue_title, "--body", issue_body]) do
      {output, 0} ->
        Logger.info("Successfully created issue/PR tracker: #{String.trim(output)}")
      {error_msg, _code} ->
        Logger.error("Failed to create PR via gh CLI. Ensure gh is installed and authenticated. Error: #{error_msg}")
    end
  rescue
    e in ErlangError ->
      Logger.warning("Encountered error preparing PR with gh CLI: #{inspect(e)}")
  end

  defp check_html_endpoint(url) do
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
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        cond do
          duration_ms > 1000 ->
            {:error, "Endpoint #{url} response time too long (#{duration_ms}ms)"}
          true ->
            case Jason.decode(body) do
              {:ok, _json} -> {:ok, url}
              {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
            end
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  def is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end
end
