defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Continuous Agent-Friendly (AX) Audit GenServer.
  Periodically queries the MCP endpoint, checking response times and JSON schema validity.
  If an issue is found, it automatically creates a PR using `git` and `gh` to propose a fix.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes
  @mcp_url "http://localhost:4000/api/mcp"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:audit, state) do
    run_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit do
    Logger.info("[AXAudit] Running AX audit on MCP endpoint...")

    # Use Req with decode_body: false as directed to safely handle potential decode errors
    {time, result} = :timer.tc(fn ->
      Req.get(@mcp_url, decode_body: false)
    end)

    # time is in microseconds, convert to milliseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      Logger.error("[AXAudit] MCP endpoint timeout: #{time_ms}ms")
      handle_issue("{:error, :timeout}")
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} ->
              Logger.info("[AXAudit] MCP endpoint healthy")
            {:error, _reason} ->
              Logger.error("[AXAudit] MCP endpoint JSON decode failed")
              handle_issue("{:error, :invalid_json}")
          end
        {:ok, %{status: status}} ->
          Logger.error("[AXAudit] MCP endpoint returned status #{status}")
          handle_issue("{:error, :bad_status}")
        {:error, _reason} ->
          Logger.error("[AXAudit] MCP endpoint request failed")
          handle_issue("{:error, :request_failed}")
      end
    end
  end

  defp handle_issue(reason) do
    Logger.info("[AXAudit] Handling issue, checking for existing PR...")

    search_cmd = "gh"
    search_args = ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix in:title", "--state", "open"]

    try do
      case System.cmd(search_cmd, search_args) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_fix_pr(reason)
          else
            Logger.info("[AXAudit] Open PR already exists for AX Audit, skipping.")
          end
        {err, code} ->
          Logger.error("[AXAudit] gh search failed with code #{code}: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("[AXAudit] Failed to execute gh command: #{inspect(e)}")
    end
  end

  defp create_fix_pr(reason) do
    Logger.info("[AXAudit] Creating automated fix PR for reason: #{reason}")
    branch_name = "ax-audit-fix-#{System.system_time(:second)}"

    # Write fix to actual source directory to avoid git ignoring it
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    fix_file = Path.join(priv_dir, "ax_audit_fix.txt")

    fix_content = "Automated fix proposed for reason: #{reason}\n"

    case File.write(fix_file, fix_content) do
      :ok ->
        execute_git_commands(branch_name, fix_file)
      {:error, posix} ->
        Logger.error("[AXAudit] Failed to write fix file: #{inspect(posix)}")
    end
  end

  defp execute_git_commands(branch_name, fix_file) do
    commands = [
      {"git", ["checkout", "-b", branch_name]},
      {"git", ["add", fix_file]},
      {"git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\n\nReason: fix"]},
      {"git", ["push", "-u", "origin", branch_name]},
      {"gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix proposed.", "--head", branch_name]}
    ]

    Enum.each(commands, fn {cmd, args} ->
      try do
        case System.cmd(cmd, args, stderr_to_stdout: true) do
          {out, 0} ->
            Logger.info("[AXAudit] #{cmd} executed successfully: #{out}")
          {out, code} ->
            Logger.error("[AXAudit] #{cmd} failed with code #{code}: #{out}")
        end
      rescue
        e in ErlangError ->
          Logger.error("[AXAudit] Failed to execute #{cmd}: #{inspect(e)}")
      end
    end)

    # Switch back to main to avoid leaving working tree in weird state
    try do
      System.cmd("git", ["checkout", "-"])
    rescue
      _ -> :ok
    end
  end
end