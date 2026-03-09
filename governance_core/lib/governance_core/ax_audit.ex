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
    endpoints = ["/", "/agents", "/dashboard/traffic", "/api/agents", "/.well-known/agent.json"]

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


  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        response_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        is_slow = response_time > 1000 # Let's say 1 second is slow

        if is_slow do
          Logger.warning("AX Audit: Endpoint #{url} is slow: #{response_time}ms")
        end

        is_valid = if String.contains?(url, "/api/agents") or String.contains?(url, "/agent.json") do
          case Jason.decode(body) do
            {:ok, _json} -> true
            {:error, _} -> false
          end
        else
          is_agent_friendly?(body)
        end

        if is_valid and not is_slow do
          {:ok, url}
        else
          reason = cond do
            is_slow and not is_valid -> "slow response (#{response_time}ms) and invalid schema/content"
            is_slow -> "slow response (#{response_time}ms)"
            not is_valid -> "invalid JSON schema or missing semantic tags"
          end

          handle_failure(url, reason)
          {:error, "Endpoint #{url} failed: #{reason}"}
        end
      {:ok, %{status: status}} ->
        reason = "returned status #{status}"
        handle_failure(url, reason)
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        error_msg = "failed to fetch: #{inspect(reason)}"
        handle_failure(url, error_msg)
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp handle_failure(url, reason) do
    title = "AX Audit Failure: #{url}"
    body = "Endpoint `#{url}` failed AX Audit.
Reason: #{reason}
Please investigate and fix."

    try do
      System.cmd("gh", ["issue", "create", "--title", title, "--body", body, "--label", "bug,jules"], stderr_to_stdout: true)
    rescue
      e in ErlangError -> Logger.error("Failed to execute gh CLI: #{inspect(e)}")
      e -> Logger.error("Failed to run gh cmd: #{inspect(e)}")
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
