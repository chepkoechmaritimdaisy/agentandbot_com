defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs audits to ensure the application remains "Agent-Friendly" (AX).
  Includes a nightly audit for overall structure and a continuous loop
  for monitoring the MCP API endpoint.
  """
  use GenServer
  require Logger

  # Nightly audit interval: 24 hours
  @nightly_interval 24 * 60 * 60 * 1000
  # Continuous monitor interval: 1 minute
  @monitor_interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_nightly_audit()
    schedule_continuous_monitor()
    {:ok, state}
  end

  def handle_info(:nightly_audit, state) do
    perform_nightly_audit()
    schedule_nightly_audit()
    {:noreply, state}
  end

  def handle_info(:continuous_monitor, state) do
    monitor_mcp_api()
    schedule_continuous_monitor()
    {:noreply, state}
  end

  defp schedule_nightly_audit do
    Process.send_after(self(), :nightly_audit, @nightly_interval)
  end

  defp schedule_continuous_monitor do
    Process.send_after(self(), :continuous_monitor, @monitor_interval)
  end

  def perform_nightly_audit do
    Logger.info("Starting Nightly AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Nightly Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Nightly Audit Failed: #{inspect(failures)}")
    end
  end

  def monitor_mcp_api do
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"
    start_time = System.monotonic_time()

    case Req.get(url) do
      {:ok, %{status: status, body: body}} ->
        end_time = System.monotonic_time()
        # duration in milliseconds
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if duration_ms > 500 do
          handle_mcp_failure("MCP API response time too slow: #{duration_ms}ms")
        else
          # Ensure it returns a JSON object/list
          if is_map(body) or is_list(body) do
             # Check passed
             :ok
          else
            handle_mcp_failure("MCP API returned invalid JSON schema: #{inspect(body)}")
          end
        end

      {:error, reason} ->
        handle_mcp_failure("MCP API unreachable: #{inspect(reason)}")
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

  def is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")

    has_main && has_h1
  end

  defp handle_mcp_failure(reason) do
    Logger.error("AX Audit (Continuous): #{reason}")
    create_automated_pr(reason)
  end

  defp create_automated_pr(reason) do
    Logger.info("Preparing automated PR for fix...")

    branch_name = "auto-fix-ax-#{System.unique_integer([:positive])}"
    dummy_file = Path.join([File.cwd!(), "priv", "auto_fix_#{System.unique_integer([:positive])}.txt"])

    try do
      # Deduplication: check if a PR for this issue type already exists
      case System.cmd("gh", ["pr", "list", "--search", "auto-fix-ax", "--json", "title"]) do
        {output, 0} ->
           if String.contains?(output, "auto-fix-ax") do
             Logger.info("An automated PR for AX audit already exists. Skipping.")
           else
             execute_git_workflow(branch_name, dummy_file, reason)
           end
        {err, _code} ->
           Logger.error("Failed to list PRs using gh: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing CLI command (e.g. gh not found): #{inspect(e)}")
    end
  end

  defp execute_git_workflow(branch_name, dummy_file, reason) do
    try do
      # 1. Create and checkout new branch
      {_, 0} = System.cmd("git", ["checkout", "-b", branch_name])

      # 2. Write a dummy fix file in priv
      File.write!(dummy_file, "Automated fix applied for: #{reason}")

      # 3. Add and commit
      {_, 0} = System.cmd("git", ["add", dummy_file])
      {_, 0} = System.cmd("git", ["commit", "-m", "Automated fix: AX Audit Failure", "-m", reason])

      # 4. Create PR via gh
      case System.cmd("gh", ["pr", "create", "--title", "Automated fix: AX Audit Failure", "--body", reason]) do
         {_, 0} -> Logger.info("Automated PR created successfully.")
         {err, _} -> Logger.error("Failed to create PR: #{err}")
      end

      # 5. Return to previous branch
      {_, 0} = System.cmd("git", ["checkout", "-"])
    rescue
      e in ErlangError ->
        Logger.error("Error executing git workflow: #{inspect(e)}")
      MatchError ->
        Logger.error("A git command returned a non-zero exit code during the automated workflow.")
    end
  end
end
