defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Monitors MCP endpoints for response time and valid JSON schema.
  Automatically creates a PR if there are errors.
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
    # Check the primary MCP API endpoint
    endpoints = ["/api/mcp"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        time_diff = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if time_diff > 2000 do
           {:error, "Response time too high"}
        else
           if is_valid_json?(body) do
             {:ok, url}
           else
             {:error, "Invalid JSON Schema"}
           end
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP Error #{status}"}

      {:error, _reason} ->
        # Use static error reason for deduplication
        {:error, "Connection Failed"}
    end
  end

  defp is_valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp handle_failures(failures) do
    # Assuming taking the first failure to create a PR
    {_, reason} = hd(failures)
    title = "Fix AX Audit Failure: #{reason}"

    # Check if a PR already exists
    case run_gh(["pr", "list", "--search", "in:title \"#{title}\"", "--state", "open", "--json", "id"]) do
      {:ok, "[]\n"} ->
        create_fix_pr(title, reason)
      {:ok, _} ->
        Logger.info("PR already exists for: #{title}")
      {:error, err} ->
        Logger.error("Failed to check existing PRs: #{inspect(err)}")
    end
  end

  defp create_fix_pr(title, reason) do
    branch_name = "fix/ax-audit-#{:os.system_time(:second)}"

    # We do a basic tree creation to push the branch without checking out
    # For now, just create an empty commit to open the PR
    with {:ok, tree_hash} <- run_git(["write-tree"]),
         tree_hash = String.trim(tree_hash),
         {:ok, commit_hash} <- run_git(["commit-tree", tree_hash, "-p", "HEAD", "-m", title]),
         commit_hash = String.trim(commit_hash),
         {:ok, _} <- run_git(["update-ref", "refs/heads/#{branch_name}", commit_hash]),
         {:ok, _} <- run_git(["push", "origin", branch_name]) do

         body = "Automated PR by AX Audit.\n\nReason: #{reason}"

         case run_gh(["pr", "create", "--title", title, "--body", body, "--head", branch_name]) do
           {:ok, output} -> Logger.info("Created PR: #{output}")
           {:error, err} -> Logger.error("Failed to create PR: #{inspect(err)}")
         end
    else
      err -> Logger.error("Failed to create git branch/commit: #{inspect(err)}")
    end
  end

  defp run_gh(args) do
    try do
      case System.cmd("gh", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    rescue
      e in ErlangError -> {:error, "gh not found or error: #{inspect(e)}"}
    end
  end

  defp run_git(args) do
    try do
      case System.cmd("git", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    rescue
      e in ErlangError -> {:error, "git not found or error: #{inspect(e)}"}
    end
  end
end
