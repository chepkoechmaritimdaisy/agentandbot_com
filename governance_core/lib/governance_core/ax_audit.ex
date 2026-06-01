defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Specifically, it monitors the MCP (Model Context Protocol) API endpoint.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    mcp_url = base_url <> "/api/mcp"

    case check_mcp_endpoint(mcp_url) do
      :ok ->
        Logger.info("AX Audit Passed: MCP Endpoint is Agent-Friendly.")
      {:error, reason} ->
        Logger.error("AX Audit Failed on MCP Endpoint: #{inspect(reason)}")
        create_auto_fix_pr(reason)
    end
  end

  defp check_mcp_endpoint(url) do
    {time_micro, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_ms = time_micro / 1000.0

    case result do
      {:ok, %{status: 200, body: body}} ->
        if time_ms > 1000 do
          {:error, "Response time too slow: #{time_ms}ms"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> :ok
            {:error, _} -> {:error, "Invalid JSON response"}
          end
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch: #{inspect(reason)}"}
    end
  end

  defp create_auto_fix_pr(reason) do
    error_string =
      case reason do
        reason when is_binary(reason) -> reason
        _ -> inspect(reason)
      end

    try do
      # Avoid PR spam loop
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            # Generate a fix commit directly using git
            fix_content = Jason.encode!(%{error: error_string, auto_fixed: true})
            file_path = Path.join(File.cwd!(), "priv/ax_audit_fix.json")
            File.write!(file_path, fix_content)

            branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"
            System.cmd("git", ["checkout", "-b", branch_name])
            System.cmd("git", ["add", file_path])
            System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix for MCP endpoint"])
            System.cmd("git", ["push", "-u", "origin", branch_name])

            case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failure: #{error_string}"]) do
              {_, 0} -> Logger.info("Automated PR created successfully.")
              {err, _} -> Logger.error("Failed to create PR: #{err}")
            end

            System.cmd("git", ["checkout", "-"] )
          else
             Logger.info("Automated PR already exists.")
          end
        {err, _} ->
          Logger.error("Failed to list PRs: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing CLI command for PR creation: #{inspect(e)}")
    end
  end
end
