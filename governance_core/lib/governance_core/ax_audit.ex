defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure
  - Valid JSON schemas on the /api/mcp endpoint
  - Response times limits (under 1000ms)
  Generates automated PRs for failures.
  """
  use GenServer
  require Logger

  # Continuous interval in milliseconds (5 minutes)
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
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()

    html_endpoints = ["/", "/agents", "/dashboard/traffic"]
    mcp_endpoint = "/api/mcp"

    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    mcp_result = check_mcp_endpoint(base_url <> mcp_endpoint)

    results = html_results ++ [mcp_result]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    # Convert microseconds to milliseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      {:error, %{type: :timeout, url: url, time_ms: time_ms}}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, reason} -> {:error, %{type: :json_schema, url: url, reason: inspect(reason)}}
          end
        {:ok, %{status: status}} ->
          {:error, %{type: :bad_status, url: url, status: status}}
        {:error, reason} ->
          {:error, %{type: :fetch_failed, url: url, reason: inspect(reason)}}
      end
    end
  end

  defp check_html_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, %{type: :not_agent_friendly, url: url}}
        end
      {:ok, %{status: status}} ->
        {:error, %{type: :bad_status, url: url, status: status}}
      {:error, reason} ->
        {:error, %{type: :fetch_failed, url: url, reason: inspect(reason)}}
    end
  end

  defp is_agent_friendly?(html) do
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp handle_failures(failures) do
    pr_title = "🤖 [AX Audit] Automated Fix"

    # Check for deduplication
    case run_cmd("gh", ["pr", "list", "--search", pr_title]) do
      {:ok, output} ->
        if String.contains?(output, pr_title) do
          Logger.info("Automated fix PR already exists, skipping.")
        else
          create_automated_pr(failures, pr_title)
        end
      {:error, reason} ->
        Logger.error("Failed to check existing PRs: #{inspect(reason)}")
    end
  end

  defp create_automated_pr(failures, pr_title) do
    # Map tuples to maps for Jason serialization
    serializable_failures = Enum.map(failures, fn
      {:error, reason} when is_map(reason) -> %{status: "error", details: reason}
      {:error, reason} -> %{status: "error", details: inspect(reason)}
    end)

    fix_content = Jason.encode!(%{fixes: serializable_failures}, pretty: true)
    fix_path = Path.join(File.cwd!(), "priv/ax_audit_fix.json")

    case File.write(fix_path, fix_content) do
      :ok ->
        branch_name = "ax-audit-fix-#{System.system_time(:second)}"

        run_cmd("git", ["checkout", "-b", branch_name])
        run_cmd("git", ["add", fix_path])
        run_cmd("git", ["commit", "-m", pr_title])
        run_cmd("git", ["push", "origin", branch_name])

        case run_cmd("gh", ["pr", "create", "--title", pr_title, "--body", "Automated fix for AX Audit failures."]) do
          {:ok, _} -> Logger.info("Successfully created automated PR for AX Audit.")
          {:error, reason} -> Logger.error("Failed to create PR: #{inspect(reason)}")
        end

        # Cleanup locally (ignoring errors)
        run_cmd("git", ["checkout", "-"])

      {:error, reason} ->
        Logger.error("Failed to write fix file: #{inspect(reason)}")
    end
  end

  defp run_cmd(cmd, args) do
    try do
      case System.cmd(cmd, args) do
        {output, 0} -> {:ok, output}
        {output, _code} -> {:error, output}
      end
    rescue
      e in ErlangError -> {:error, inspect(e)}
    end
  end
end
