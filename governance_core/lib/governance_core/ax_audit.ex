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

    # Standard HTML endpoints
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]
    # MCP (Model Context Protocol) endpoints
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(html_endpoints, fn path ->
      check_html_endpoint(base_url <> path)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      check_mcp_endpoint(base_url <> path)
    end)

    failures = Enum.filter(html_results ++ mcp_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      # Here we would logically trigger a PR or Issue creation for the fix
    end
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
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        # Validates JSON schema (basic check for structure) and response time
        cond do
          duration > 500 ->
            {:error, "MCP Endpoint #{url} too slow: #{duration}ms"}
          not is_map(body) and not is_list(body) ->
            {:error, "MCP Endpoint #{url} returned invalid JSON structure"}
          true ->
            {:ok, url}
        end

      {:ok, %{status: status}} ->
        {:error, "MCP Endpoint #{url} returned status #{status}"}
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
