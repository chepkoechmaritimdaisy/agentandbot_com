defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that dynamically tracks and updates SKILL.md documentation
  according to universal standards.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Check every hour

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

  def update_skills do
    Logger.info("Starting SKILL.md standardization update...")

    modules =
      Code.all_loaded()
      |> Enum.map(fn {mod, _file} -> mod end)
      |> Enum.filter(fn mod -> String.starts_with?(to_string(mod), "Elixir.GovernanceCore.") end)

    skills_content =
      modules
      |> Enum.map(&extract_skill_info/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    File.write!("SKILL.md", skills_content)
    Logger.info("SKILL.md updated successfully.")
  end

  defp extract_skill_info(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, mod_doc, _meta, _docs} ->
        doc_string = extract_doc_string(mod_doc)

        if doc_string && String.length(doc_string) > 0 do
          # Truncate to 1024 characters for standard
          truncated_doc = String.slice(doc_string, 0, 1024)

          # Indent for YAML block scalar
          indented_doc =
            truncated_doc
            |> String.split("\n")
            |> Enum.map(fn line -> "  " <> line end)
            |> Enum.join("\n")

          """
          ---
          name: #{inspect(module)}
          description: |
          #{indented_doc}
          version: 1.0.0
          ---
          """
        else
          nil
        end
      _ ->
        nil
    end
  end

  defp extract_doc_string(%{"en" => doc}), do: doc
  defp extract_doc_string(doc) when is_binary(doc), do: doc
  defp extract_doc_string(_), do: nil
end
