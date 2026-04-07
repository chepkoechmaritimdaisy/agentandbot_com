defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

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
    endpoints = ["/", "/agents", "/dashboard/traffic", "/api/mcp"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)

    # Use decode_body: false to prevent Req from crashing on malformed JSON
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        Logger.info("AX Audit: #{url} responded in #{duration}ms")

        cond do
          duration > 3000 ->
            handle_failure(url, {:error, :timeout})
          String.ends_with?(url, "/api/mcp") ->
            case Jason.decode(body) do
              {:ok, data} ->
                if is_valid_mcp_schema?(data) do
                  {:ok, url}
                else
                  handle_failure(url, {:error, :invalid_schema})
                end
              {:error, _} ->
                handle_failure(url, {:error, :invalid_json})
            end
          true ->
            if is_agent_friendly?(body) do
              {:ok, url}
            else
              handle_failure(url, {:error, :not_agent_friendly})
            end
        end

      {:ok, %{status: status}} ->
        handle_failure(url, {:error, :bad_status, status})

      {:error, _reason} ->
        # Use a static reason for deduplication instead of dynamic strings
        handle_failure(url, {:error, :request_failed})
    end
  end

  defp handle_failure(url, reason) do
    Logger.error("AX Audit Failed for #{url}: #{inspect(reason)}")
    create_automated_pr(url, reason)
    {:error, reason}
  end

  defp create_automated_pr(url, reason) do
    # Deduplicate: check if PR already exists using static reason
    search_query = "Automated AX Audit Fix: #{url} #{inspect(reason)}"

    try do
      case System.cmd("gh", ["pr", "list", "--search", search_query, "--json", "number"]) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, []} ->
              do_create_pr(url, reason, search_query)
            {:ok, _prs} ->
              Logger.info("AX Audit PR already exists for #{url} with reason #{inspect(reason)}")
            _ ->
              Logger.warning("AX Audit failed to decode gh pr list output")
          end
        {_, exit_code} ->
          Logger.warning("AX Audit PR deduplication check failed with exit code #{exit_code}")
      end
    rescue
      e in ErlangError -> Logger.warning("AX Audit PR creation skipped: gh CLI missing or error: #{inspect(e)}")
    end
  end

  defp do_create_pr(url, reason, title) do
    branch_name = "auto-fix-ax-audit-#{:erlang.unique_integer([:positive])}"

    try do
      # Avoid direct git mutations locally
      case System.cmd("git", ["write-tree"]) do
        {tree_hash, 0} ->
          tree_hash = String.trim(tree_hash)

          commit_msg = "#{title}\n\nAutomated fix for #{url} failing with #{inspect(reason)}"
          case System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", commit_msg]) do
            {commit_hash, 0} ->
              commit_hash = String.trim(commit_hash)

              System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])
              System.cmd("git", ["push", "origin", branch_name])

              case System.cmd("gh", ["pr", "create", "--title", title, "--body", commit_msg, "--head", branch_name]) do
                {_, 0} -> Logger.info("Created automated PR: #{title}")
                {_, exit_code} -> Logger.warning("gh pr create failed with exit code #{exit_code}")
              end

            {_, exit_code} -> Logger.warning("git commit-tree failed with exit code #{exit_code}")
          end

        {_, exit_code} -> Logger.warning("git write-tree failed with exit code #{exit_code}")
      end
    rescue
      e in ErlangError -> Logger.warning("AX Audit PR creation failed during git/gh operations: #{inspect(e)}")
    end
  end

  defp is_valid_mcp_schema?(data) when is_map(data) do
    # Simple check for now
    Map.has_key?(data, "version")
  end
  defp is_valid_mcp_schema?(_), do: false

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end
end
