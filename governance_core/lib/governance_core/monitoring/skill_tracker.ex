defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically tracks tools and features and generates SKILL.md files
  conforming to the universal standard (1024 char limit, YAML format).
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Run every hour

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
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    docs = Enum.map(modules, fn mod ->
      doc = get_module_doc(mod)
      %{
        module: to_string(mod),
        doc: doc
      }
    end)

    write_chunks(docs, "SKILL", 1, [], 0)
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} -> doc
      _ -> "No documentation available."
    end
  end

  defp write_chunks([], _base_name, _index, [], _current_len), do: :ok
  defp write_chunks([], base_name, index, current_chunk, _current_len) do
    write_chunk_file(base_name, index, Enum.reverse(current_chunk))
  end

  defp write_chunks([doc | rest], base_name, index, current_chunk, current_len) do
    yaml_item = "- module: \"#{doc.module}\"\n  doc: \"#{escape_yaml(doc.doc)}\"\n"
    item_len = String.length(yaml_item)

    if current_len + item_len > 1024 and current_chunk != [] do
      write_chunk_file(base_name, index, Enum.reverse(current_chunk))
      write_chunks([doc | rest], base_name, index + 1, [], 0)
    else
      write_chunks(rest, base_name, index, [yaml_item | current_chunk], current_len + item_len)
    end
  end

  defp write_chunk_file(base_name, index, chunk) do
    file_name = if index == 1, do: "#{base_name}.md", else: "#{base_name}_#{index}.md"
    file_path = Path.join([Application.app_dir(:governance_core), "priv", file_name])

    content = "---\ntitle: GovernanceCore Skills\n---\n" <> Enum.join(chunk)

    case File.write(file_path, content) do
      :ok -> Logger.info("Updated #{file_name}")
      {:error, reason} -> Logger.error("Failed to write #{file_name}: #{inspect(reason)}")
    end
  end

  defp escape_yaml(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end
end
