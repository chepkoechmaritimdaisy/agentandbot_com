defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and maintains a standardized SKILL.md file by tracking dynamically
  discovered tools and functions within the GovernanceCore application.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update_skills, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def perform_update do
    Logger.info("Starting SKILL.md Update...")

    {:ok, modules} = :application.get_key(:governance_core, :modules)

    yaml_entries =
      modules
      |> Enum.map(&extract_module_info/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n---\n")

    content = """
    # Agent Tools & Skills

    This document outlines the tools and capabilities available in the GovernanceCore application.

    ---
    #{yaml_entries}
    """

    File.write!("SKILL.md", content)
    Logger.info("Finished SKILL.md Update.")
  end

  defp extract_module_info(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _beam_lang, _format, %{"en" => doc_string}, _metadata, _docs} ->
        # Extract up to 1024 characters
        truncated_doc = String.slice(doc_string, 0, 1024)

        # Indent each line for valid YAML block scalar
        indented_doc =
          truncated_doc
          |> String.split("\n")
          |> Enum.map(fn line -> "  #{line}" end)
          |> Enum.join("\n")

        """
        tool: #{inspect(module)}
        description: |
        #{indented_doc}
        """
      _ ->
        nil
    end
  end
end
