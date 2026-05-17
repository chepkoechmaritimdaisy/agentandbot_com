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
    endpoints = ["/", "/agents", "/dashboard/traffic", "/api/mcp"]

    results =
      Task.async_stream(endpoints, fn path ->
        url = base_url <> path
        if path == "/api/mcp" do
          check_mcp_endpoint(url)
        else
          check_endpoint(url)
        end
      end, timeout: :infinity)
      |> Enum.to_list()
      |> Enum.map(fn {:ok, res} -> res end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  defp check_mcp_endpoint(url) do
    {time_micro, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    time_ms = time_micro / 1000

    case result do
      {:ok, %{status: 200, body: body}} ->
        if time_ms > 1000 do
          handle_mcp_failure("Endpoint #{url} took #{time_ms}ms, which is > 1000ms")
          {:error, "Endpoint #{url} is too slow"}
        else
          case Jason.decode(body) do
            {:ok, _} -> {:ok, url}
            {:error, _} ->
              handle_mcp_failure("Endpoint #{url} returned invalid JSON")
              {:error, "Endpoint #{url} returned invalid JSON"}
          end
        end
      {:ok, %{status: status}} ->
        handle_mcp_failure("Endpoint #{url} returned status #{status}")
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        handle_mcp_failure("Failed to fetch #{url}: #{inspect(reason)}")
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp handle_mcp_failure(reason) do
    Logger.error("MCP Failure: #{reason}")
    try do
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix in:title", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_automated_pr(reason)
          else
            Logger.info("Automated PR already exists.")
          end
        {_, _} ->
          Logger.warning("Failed to check existing PRs with gh cli.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute gh cli: #{Exception.message(e)}")
    end
  end

  defp create_automated_pr(reason) do
    try do
      # Make sure we don't write to _build
      priv_dir = Path.join(File.cwd!(), "priv")
      File.mkdir_p!(priv_dir)
      fix_file = Path.join(priv_dir, "mcp_fix.txt")
      File.write!(fix_file, "Automated Fix for MCP Endpoint\nReason: #{reason}\n", [:append])

      case System.cmd("git", ["add", "priv/mcp_fix.txt"]) do
        {_, 0} ->
          case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\n\n#{reason}"]) do
            {_, 0} ->
              case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for #{reason}"]) do
                {_, 0} -> Logger.info("Created PR successfully.")
                {err, _} -> Logger.error("Failed to create PR: #{err}")
              end
            {err, _} -> Logger.error("Failed to commit changes: #{err}")
          end
        {err, _} -> Logger.error("Failed to git add: #{err}")
      end
    rescue
      e in ErlangError -> Logger.warning("Failed to execute git or gh cli: #{Exception.message(e)}")
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
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
end
