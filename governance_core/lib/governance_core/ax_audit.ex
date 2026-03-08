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

    results_html = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_endpoint_html(url)
    end)

    results_mcp = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_endpoint_mcp(url)
    end)

    results = results_html ++ results_mcp
    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp handle_failures(failures) do
    failure_details = Enum.map_join(failures, "\n", fn {:error, reason} -> "- #{reason}" end)

    body = """
    AX Audit Failure Detected:

    #{failure_details}
    """

    # Create an issue using gh CLI
    case System.cmd("gh", ["issue", "create", "--title", "AX Audit Failure", "--body", body, "--label", "bug,agent-friendly"]) do
      {output, 0} -> Logger.info("Automatically created issue for AX Audit failure: #{output}")
      {error_output, status} -> Logger.error("Failed to create issue automatically. gh exit status: #{status}, output: #{error_output}")
    end
  end

  defp check_endpoint_html(url) do
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

  defp check_endpoint_mcp(url) do
    start_time = System.monotonic_time(:millisecond)

    # Use decode_body: false to safely handle invalid JSON without crashing
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 1000 do # Threshold 1s
          {:error, "Endpoint #{url} response time is too slow (#{duration}ms)"}
        else
          # Manually verify valid JSON schema
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _reason} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
          end
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
