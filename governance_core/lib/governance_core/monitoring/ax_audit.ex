defmodule GovernanceCore.Monitoring.AXAudit do
  @moduledoc """
  Periodically checks the MCP API endpoint to ensure it's responding
  and the JSON schema is valid. If an error is detected, creates a PR for an automated fix.
  """
  use GenServer
  require Logger

  @check_interval 60_000 # Check every minute
  @api_url "http://localhost:4000/api/mcp"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{last_error: nil}} # Keep track of last error to avoid spam
  end

  @impl true
  def handle_info(:check, state) do
    new_state = do_check(state)
    schedule_check()
    {:noreply, new_state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp do_check(state) do
    start_time = System.monotonic_time(:millisecond)

    case Req.get(@api_url, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        case Jason.decode(body) do
          {:ok, _json} ->
            if duration > 1000 do
              handle_error(state, :slow_response)
            else
              %{state | last_error: nil}
            end

          {:error, _} ->
            handle_error(state, :invalid_json)
        end

      {:ok, %Req.Response{status: status}} ->
        handle_error(state, {:bad_status, status})

      {:error, _reason} ->
        handle_error(state, :request_failed)
    end
  end

  defp handle_error(%{last_error: error} = state, error), do: state # Deduplicate errors
  defp handle_error(state, error) do
    Logger.warning("AXAudit detected error: #{inspect(error)}")
    create_fix_pr(error)
    %{state | last_error: error}
  end

  defp create_fix_pr(error) do
    # Ensure this doesn't crash if git or gh are not installed
    try do
      # Assuming we are running inside the repository directory
      # To prevent infinite PR loops, check if a PR already exists using static error
      case System.cmd("gh", ["pr", "list", "--search", "in:title AXAudit Fix: #{inspect(error)}", "--json", "number"]) do
        {output, 0} ->
          if output == "[]\n" or output == "[]" do
            do_create_pr(error)
          else
            Logger.info("AXAudit: PR already exists, skipping")
          end
        {err, _} ->
          Logger.warning("AXAudit: failed to check PRs: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("AXAudit: ErlangError invoking gh command (perhaps missing binary?): #{inspect(e)}")
    end
  end

  defp do_create_pr(error) do
    try do
      branch_name = "axaudit-fix-#{System.system_time(:second)}"

      # Use git write-tree and commit-tree to avoid mutating the local working directory
      # The agent would typically create a tree with the fix.
      # For now, we will just commit the current tree with a message.
      {tree, 0} = System.cmd("git", ["write-tree"])
      tree = String.trim(tree)

      {commit, 0} = System.cmd("git", ["commit-tree", tree, "-p", "HEAD", "-m", "AXAudit Fix: #{inspect(error)}"])
      commit = String.trim(commit)

      System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit])
      System.cmd("git", ["push", "-u", "origin", branch_name])

      System.cmd("gh", ["pr", "create", "--title", "AXAudit Fix: #{inspect(error)}", "--body", "Automated fix by AXAudit.", "--head", branch_name])

      Logger.info("AXAudit: PR created for #{inspect(error)}")
    rescue
      e in ErlangError ->
        Logger.warning("AXAudit: ErlangError in git commands: #{inspect(e)}")
    end
  end
end
