defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly security audit for Human-in-the-loop agent traffic.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{last_byte_pos: pos} = state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      case File.open(@log_file, [:read]) do
        {:ok, file} ->
          :file.position(file, pos)

          # Read lines until EOF
          vulnerabilities = scan_lines(file, [])

          # Get new position
          {:ok, new_pos} = :file.position(file, :cur)

          File.close(file)

          if not Enum.empty?(vulnerabilities) do
            create_security_pr(vulnerabilities)
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
          state
      end
    else
      Logger.info("Agent traffic log not found, skipping.")
      state
    end
  end

  defp scan_lines(file, vulns) do
    case IO.read(file, :line) do
      :eof ->
        vulns
      line ->
        # "Decompiler Standard" heuristic check
        new_vulns =
          if String.contains?(line, "UNAUTHORIZED_ACCESS") or String.contains?(line, "VULNERABILITY") do
            [line | vulns]
          else
            vulns
          end
        scan_lines(file, new_vulns)
    end
  end

  defp create_security_pr(vulnerabilities) do
    Logger.info("Vulnerabilities found! Creating Security PR...")

    branch_name = "security-fix-#{System.unique_integer([:positive])}"
    title = "🔒 [security fix description]"
    body = "What: Found unauthorized access or vulnerability patterns in agent traffic.\nRisk: High.\nSolution: Review log and update access controls."

    try do
      {tree_hash, 0} = System.cmd("git", ["write-tree"])
      tree_hash = String.trim(tree_hash)

      {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", title])
      commit_hash = String.trim(commit_hash)

      {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])

      {_, push_exit} = System.cmd("git", ["push", "origin", branch_name])

      if push_exit == 0 do
        System.cmd("gh", ["pr", "create",
                          "--title", title,
                          "--body", body,
                          "--head", branch_name,
                          "--base", "main"])
        Logger.info("Successfully created Security PR.")
      else
        Logger.error("Failed to push branch for Security PR.")
      end
    rescue
      e -> Logger.error("Failed to create automated PR: #{inspect(e)}")
    end
  end
end
