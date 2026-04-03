defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md files for agent tools using YAML format,
  adhering to a 1024-character limit.
  """
  use GenServer
  require Logger

  # Update every hour
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    Logger.info("Starting SKILL.md update...")

    # Fetch loaded modules using :application.get_key
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        # Here we could filter for specific modules that represent "tools"
        # For demonstration, we just pick some protocol modules or AXAudit
        |> Enum.filter(fn mod ->
          name = inspect(mod)
          String.contains?(name, "GovernanceCore.AXAudit") or String.contains?(name, "GovernanceCore.Protocols.Fuzzer")
        end)
        |> Enum.each(&process_module/1)
      _ ->
        Logger.warning("Failed to get modules from application.")
    end
  end

  defp process_module(mod) do
    name = inspect(mod)
    description = get_moduledoc(mod)

    # Truncate content string before interpolating it into YAML template
    # to prevent breaking the YAML structure
    max_desc_length = 800
    truncated_desc =
      if String.length(description) > max_desc_length do
        String.slice(description, 0, max_desc_length) <> "..."
      else
        description
      end

    # Explicitly indent multiline strings line-by-line
    indented_desc =
      truncated_desc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    yaml_content = """
    ---
    name: #{name}
    version: 1.0.0
    description: |
    #{indented_desc}
    ---
    """

    # Apply 1024 char limits before writing
    final_content = String.slice(yaml_content, 0, 1024)

    # Write to a directory named after the module inside 'skills/'
    dir_path = "skills/#{name}"
    File.mkdir_p!(dir_path)
    file_path = Path.join(dir_path, "SKILL.md")
    File.write!(file_path, final_content)

    Logger.info("Wrote SKILL.md for #{name} to #{file_path}")
  end

  defp get_moduledoc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} ->
        doc
      _ ->
        "No documentation available."
    end
  end
end
