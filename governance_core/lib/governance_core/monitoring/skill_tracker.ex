defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and updates SKILL.md documentation for the project's modules, enforcing universal agent standards (YAML format, 1024 char limit per file).
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @char_limit 1024

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&module_to_skill/1)
        |> chunk_and_write()

      _ ->
        Logger.warning("SkillTracker: Could not retrieve modules.")
    end
  end

  defp module_to_skill(module) do
    name = inspect(module)
    doc =
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, "text/markdown", %{"en" => module_doc}, _, _} -> module_doc
        _ -> "No documentation available."
      end

    %{
      "name" => name,
      "description" => doc
    }
  end

  defp chunk_and_write(skills) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    skills
    |> Enum.reduce({[], 0, 1}, fn skill, {current_chunk, current_len, file_index} ->
      # Approximate YAML serialization length
      yaml_entry = "- name: #{skill[\"name\"]}\n  description: #{inspect(skill[\"description\"])}\n"
      entry_len = String.length(yaml_entry)

      if current_len + entry_len > @char_limit and current_chunk != [] do
        write_chunk(Enum.reverse(current_chunk), file_index, priv_dir)
        {[skill], entry_len, file_index + 1}
      else
        {[skill | current_chunk], current_len + entry_len, file_index}
      end
    end)
    |> then(fn {last_chunk, _, file_index} ->
      if last_chunk != [] do
        write_chunk(Enum.reverse(last_chunk), file_index, priv_dir)
      end
    end)
  end

  defp write_chunk(chunk, index, priv_dir) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    file_path = Path.join(priv_dir, filename)

    yaml_content =
      chunk
      |> Enum.map(fn s -> "- name: #{s[\"name\"]}\n  description: #{inspect(s[\"description\"])}\n" end)
      |> Enum.join("")

    File.write!(file_path, "---\n" <> yaml_content)
    Logger.info("SkillTracker: Updated #{filename}")
  end
end
