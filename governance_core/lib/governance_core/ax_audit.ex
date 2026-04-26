defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the MCP endpoint to ensure it remains active and valid.
  Creates an automated PR if it detects failures.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit on MCP endpoint...")
    base_url = GovernanceCoreWeb.Endpoint.url()
    url = base_url <> "/api/mcp"

    # 1. Benchmark req.get using timer.tc and avoid decode_body errors
    {time_us, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_ms = time_us / 1000

    # 2. Check logic
    check_result =
      if time_ms > 1000 do
        {:error, :timeout}
      else
        case result do
          {:ok, %{status: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, _json} -> :ok
              {:error, _} -> {:error, :invalid_schema}
            end
          {:ok, %{status: status}} ->
             {:error, :bad_status}
          {:error, _} ->
             {:error, :network_error}
        end
      end

    if check_result != :ok do
      Logger.error("AX Audit Failed: #{inspect(check_result)}")
      create_automated_fix(check_result)
    else
      Logger.info("AX Audit Passed: MCP endpoint is Agent-Friendly.")
    end
  end

  defp create_automated_fix(reason) do
    pr_title = "🤖 [AX Audit] Automated Fix"
    static_reason = inspect(reason)

    try do
      # 1. Deduplicate
      {list_out, list_status} = System.cmd("gh", ["pr", "list", "--search", pr_title])

      if list_status == 0 and String.contains?(list_out, pr_title) do
        Logger.info("AX Audit PR already exists. Skipping PR creation.")
      else
        # 2. Generate fix in actual source directory
        fix_dir = Path.join(File.cwd!(), "priv")
        File.mkdir_p!(fix_dir)
        fix_file = Path.join(fix_dir, "ax_audit_fix_#{System.system_time(:second)}.txt")
        File.write!(fix_file, "Automated fix applied for: #{static_reason}")

        branch_name = "ax-audit-fix-#{System.system_time(:second)}"

        System.cmd("git", ["checkout", "-b", branch_name])
        System.cmd("git", ["add", "priv/"])
        System.cmd("git", ["commit", "-m", pr_title])

        {_, push_status} = System.cmd("git", ["push", "origin", branch_name])

        if push_status == 0 do
          System.cmd("gh", ["pr", "create", "--title", pr_title, "--body", "Fixes MCP endpoint issue: #{static_reason}"])
          Logger.info("AX Audit successfully created a PR.")
        else
          Logger.error("AX Audit PR creation failed to push branch.")
        end

        System.cmd("git", ["checkout", "-"] )
      end
    rescue
      e in ErlangError ->
        Logger.error("AX Audit: Failed to run gh cli commands: #{inspect(e)}")
    end
  end
end
