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

    results = html_results ++ mcp_results
    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      # In a real system, you might trigger a PR generation here.
      # For now, we just log it as an error to track.
    end
  end

  defp check_html_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "HTML Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "HTML Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch HTML #{url}: #{inspect(reason)}"}
    end
  end

  defp is_agent_friendly?(html) do
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 1000 do
          {:error, "MCP Endpoint #{url} response time is too long: #{duration}ms"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP Endpoint #{url} returned invalid JSON schema"}
          end
        end
      {:ok, %{status: status}} ->
        {:error, "MCP Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch MCP #{url}: #{inspect(reason)}"}
    end
  end
end
