defmodule GovernanceCore.Monitoring.AXAudit do
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute
  @endpoint "http://localhost:4000/api/mcp"
  @timeout 5000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{last_error_reason: nil}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state =
      case perform_audit() do
        :ok ->
          %{state | last_error_reason: nil}

        {:error, reason} ->
          if reason != state.last_error_reason do
            Logger.warning("AX Audit found issue: #{reason}")
            create_automated_pr(reason)
            %{state | last_error_reason: reason}
          else
            state
          end
      end

    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit do
    start_time = System.monotonic_time()

    case Req.get(@endpoint, decode_body: false, receive_timeout: @timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if duration_ms > 1000 do
          {:error, :timeout_exceeded}
        else
          case Jason.decode(body) do
            {:ok, _json} -> :ok
            {:error, _} -> {:error, :invalid_json_schema}
          end
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, :non_200_status}

      {:error, _} ->
        {:error, :request_failed}
    end
  end

  defp create_automated_pr(reason) do
    branch_name = "fix/ax-audit-#{:os.system_time(:second)}"
    msg = "Automated fix for AX Audit issue: #{reason}"

    try do
      # Deduplicate - check if PR already exists
      case System.cmd("gh", ["pr", "list", "--search", "in:title \"#{msg}\"", "--json", "id"]) do
        {output, 0} ->
          if output == "[]\n" or output == "[]" do
            do_create_pr(branch_name, msg)
          else
            Logger.info("PR already exists for reason: #{reason}")
          end
        _ ->
          Logger.error("Failed to list PRs with gh")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error running gh: #{inspect(e)}")
    end
  end

  defp do_create_pr(branch_name, msg) do
    try do
      # Avoid direct local git mutations, use git tree operations as per guidelines
      {tree_hash, 0} = System.cmd("git", ["write-tree"])
      tree_hash = String.trim(tree_hash)

      {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", msg])
      commit_hash = String.trim(commit_hash)

      System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])
      System.cmd("git", ["push", "origin", branch_name])

      System.cmd("gh", ["pr", "create", "--title", msg, "--body", "Automated PR created by AX Audit", "--head", branch_name])
    rescue
      e in ErlangError ->
         Logger.error("Error creating PR: #{inspect(e)}")
    end
  end
end
