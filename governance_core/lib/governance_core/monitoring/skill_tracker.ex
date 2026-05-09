defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and chunks SKILL.md YAML documentation for the application's modules.
  Enforces a strict 1024 character limit per generated markdown file.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skills_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skills_docs do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_chunks = chunk_modules_to_yaml(modules)

        Enum.with_index(yaml_chunks, 1)
        |> Enum.each(fn {yaml_content, index} ->
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          filepath = Path.join(File.cwd!(), "priv/#{filename}")

          case File.write(filepath, yaml_content) do
            :ok -> Logger.info("Successfully updated #{filename}")
            {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
          end
        end)

      :undefined ->
        Logger.error("Failed to get modules for :governance_core")
    end
  end

  defp chunk_modules_to_yaml(modules) do
    do_chunk(modules, [], "")
  end

  defp do_chunk([], chunks, current_chunk) do
    if current_chunk == "" do
      Enum.reverse(chunks)
    else
      Enum.reverse([current_chunk | chunks])
    end
  end

  defp do_chunk([module | rest], chunks, current_chunk) do
    module_str = to_string(module)
    docs = get_module_doc(module)

    # Indent multiline strings properly for YAML
    indented_docs =
      docs
      |> String.split("\n")
      |> Enum.map(&("      #{&1}"))
      |> Enum.join("\n")

    yaml_entry = """
    - module: #{module_str}
      description: |
#{indented_docs}
    """

    new_length = String.length(current_chunk) + String.length(yaml_entry)

    if new_length > 1024 do
      # If current chunk is empty, this single entry is over 1024. Just push it anyway to avoid infinite loop.
      if current_chunk == "" do
        do_chunk(rest, [yaml_entry | chunks], "")
      else
        do_chunk([module | rest], [current_chunk | chunks], "")
      end
    else
      do_chunk(rest, chunks, current_chunk <> yaml_entry)
    end
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} -> doc
      _ -> "No documentation available."
    end
  end
end
