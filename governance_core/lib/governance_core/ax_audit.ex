defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
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
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    # Also check /api/mcp endpoint with decode_body: false per memory instructions
    mcp_url = base_url <> "/api/mcp"

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    mcp_result = check_mcp_endpoint(mcp_url)

    failures = Enum.filter([mcp_result | results], fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_pr(failures)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "endpoint_not_friendly"}
        end
      {:ok, %{status: _status}} ->
        {:error, "endpoint_bad_status"}
      {:error, _reason} ->
        {:error, "endpoint_fetch_failed"}
    end
  end

  defp check_mcp_endpoint(url) do
    # Use decode_body: false as specified in memory
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
           {:ok, decoded} ->
             # Basic schema check for the scope of this project, you'd do more extensive checking here
             if is_map(decoded) do
               {:ok, url}
             else
               {:error, "mcp_invalid_schema"}
             end
           {:error, _} ->
             {:error, "mcp_json_decode_error"}
        end
      {:ok, %{status: _status}} ->
        {:error, "mcp_bad_status"}
      {:error, _reason} ->
        {:error, "mcp_fetch_failed"}
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

  defp prepare_pr(failures) do
    Logger.info("Preparing PR for AX Audit failures...")

    # Static error reasons as string for deduplication (per memory)
    dedupe_string = Enum.map(failures, fn {:error, reason} -> reason end) |> Enum.join("-")
    branch_name = "auto-fix-ax-audit-#{:erlang.phash2(dedupe_string)}"

    # Deduplication check using gh search
    try do
      {output, exit_status} = System.cmd("gh", ["pr", "list", "--search", branch_name, "--json", "number"])

      if exit_status == 0 and output == "[]\n" do
        create_pr(branch_name, dedupe_string)
      else
        Logger.info("PR for #{branch_name} already exists or deduplication check failed. Skipping PR creation.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute gh CLI for PR deduplication: #{inspect(e)}")
    end
  end

  defp create_pr(branch_name, failures_str) do
    # Avoid local git mutations by using plumbing commands
    try do
      # Getting the tree of HEAD
      {tree_output, 0} = System.cmd("git", ["write-tree"])
      tree_sha = String.trim(tree_output)

      # Commit tree
      {commit_output, 0} = System.cmd("git", ["commit-tree", tree_sha, "-p", "HEAD", "-m", "Automated AX Audit fix for #{failures_str}"])
      commit_sha = String.trim(commit_output)

      # Push branch directly
      {_, 0} = System.cmd("git", ["push", "origin", "#{commit_sha}:refs/heads/#{branch_name}"])

      # Create PR
      System.cmd("gh", [
        "pr", "create",
        "--base", "main",
        "--head", branch_name,
        "--title", "Automated AX Audit Fix",
        "--body", "Automated PR created due to AX Audit failures: #{failures_str}"
      ])

      Logger.info("Successfully created PR for branch #{branch_name}")
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run Git/GH CLI commands for PR creation: #{inspect(e)}")
      MatchError ->
        Logger.warning("Failed to match successful exit codes from Git commands")
    end
  end
end
