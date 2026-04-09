defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - MCP endpoints for valid JSON schema
  - Response time
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{recent_prs: []}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(state) do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/api/agents", "/.well-known/agent.json"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All MCP endpoints are Agent-Friendly.")
      state
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures, state)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        time_diff = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if time_diff > 1000 do
           {:error, "Endpoint #{url} response time too long"}
        else
           case Jason.decode(body) do
             {:ok, _} -> {:ok, url}
             {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
           end
        end

      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}

      {:error, _reason} ->
        {:error, "Failed to fetch #{url}"}
    end
  end

  defp handle_failures(failures, state) do
    Enum.reduce(failures, state, fn {:error, reason}, acc ->
      if Enum.member?(acc.recent_prs, reason) do
        Logger.info("AX Audit: PR for '#{reason}' already created recently. Skipping.")
        acc
      else
        branch_name = "ax-audit-fix-#{:os.system_time(:second)}"
        Logger.warning("AX Audit: Attempting to create PR for '#{reason}' on branch #{branch_name}...")

        try do
          System.cmd("gh", [
            "pr", "create",
            "--title", "fix: AX Audit automated fix for MCP endpoint",
            "--body", "Automated fix for: #{reason}",
            "--head", branch_name,
            "--base", "main"
          ])
        rescue
          e in ErlangError ->
            Logger.warning("AX Audit: `gh` CLI not found. Could not create PR. Exception: #{inspect(e)}")
        end

        %{acc | recent_prs: [reason | acc.recent_prs]}
      end
    end)
  end
end
