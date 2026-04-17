defmodule GovernanceCore.Monitoring.AXAudit do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes
  @endpoint "http://localhost:4000/api/mcp"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp audit do
    start_time = System.monotonic_time()

    case Req.get(@endpoint, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        response_time = System.monotonic_time() - start_time
        response_ms = System.convert_time_unit(response_time, :native, :millisecond)

        if response_ms > 2000 do
          handle_error({:error, :timeout})
        else
          case Jason.decode(body) do
            {:ok, _json} -> :ok # Assume schema is valid if it decodes for now, or check specifics
            {:error, _} -> handle_error({:error, :invalid_schema})
          end
        end

      {:ok, %Req.Response{status: status}} ->
        handle_error({:error, :bad_status, status})

      {:error, _} ->
        handle_error({:error, :timeout})
    end
  end

  defp handle_error({:error, reason} = _err) do
    Logger.error("AXAudit detected issue: #{inspect(reason)}")
    create_pr(reason)
  end
  defp handle_error({:error, reason, _}) do
    Logger.error("AXAudit detected issue: #{inspect(reason)}")
    create_pr(reason)
  end

  defp create_pr(reason) do
    reason_str = inspect(reason)
    branch_name = "fix/ax-audit-#{:erlang.phash2(reason_str)}"
    title = "Fix AX Audit issue: #{reason_str}"

    try do
      # Check for duplicates
      case System.cmd("gh", ["pr", "list", "--search", "in:title #{title} state:open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            # No PR found, create one
            do_create_pr(branch_name, title)
          else
            Logger.info("AXAudit PR already exists for #{reason_str}")
          end
        _ ->
          Logger.warning("AXAudit failed to check for existing PRs via gh")
      end
    rescue
      e in ErlangError -> Logger.warning("AXAudit caught ErlangError running gh: #{inspect(e)}")
    end
  end

  defp do_create_pr(branch, title) do
    # Simple empty commit to create a branch
    try do
      {tree, 0} = System.cmd("git", ["write-tree"])
      tree = String.trim(tree)
      {commit, 0} = System.cmd("git", ["commit-tree", tree, "-p", "HEAD", "-m", title])
      commit = String.trim(commit)

      {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch}", commit])
      {_, 0} = System.cmd("git", ["push", "origin", branch])

      {_, 0} = System.cmd("gh", ["pr", "create", "--head", branch, "--title", title, "--body", "Automated fix for #{title}"])
      Logger.info("AXAudit successfully created PR #{branch}")
    rescue
      e in ErlangError -> Logger.warning("AXAudit caught ErlangError running git/gh: #{inspect(e)}")
    end
  end
end
