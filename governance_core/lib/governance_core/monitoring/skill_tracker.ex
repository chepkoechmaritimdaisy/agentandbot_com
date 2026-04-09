defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that auto-detects new functions and updates SKILL.md documentation
  according to evrensel standards (YAML format, 1024-character limit).
  """
  use GenServer
  require Logger

  # 1 hour in milliseconds
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp perform_check do
    Logger.info("Starting SkillTracker check...")

    # Dynamically discover functions/tools from all loaded GovernanceCore modules.
    new_tools =
      :code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod -> String.starts_with?(to_string(mod), "Elixir.GovernanceCore") end)
      |> Enum.flat_map(fn mod ->
        try do
          case Code.fetch_docs(mod) do
            {:docs_v1, _, _, _, _, _, docs} ->
              Enum.flat_map(docs, fn
                {{:function, name, arity}, _anno, _signatures, %{"en" => doc_string}, _metadata} ->
                  [
                    %{
                      name: "#{mod}.#{name}/#{arity}",
                      description: String.trim(doc_string),
                      version: "1.0.0" # Assuming a default version or extracting from metadata
                    }
                  ]
                _ ->
                  []
              end)
            _ -> []
          end
        rescue
          _ -> []
        end
      end)

    Enum.each(new_tools, &update_skill_md/1)

    Logger.info("SkillTracker check completed.")
  end

  defp update_skill_md(tool) do
    skill_file = "SKILL.md"

    # Ensure format uses YAML frontmatter
    yaml_entry = """
    ---
    name: #{tool.name}
    description: #{tool.description}
    version: #{tool.version}
    ---
    """

    # Enforce 1024-character limit
    limited_entry = String.slice(yaml_entry, 0, 1024)

    # Check if tool already exists
    content = if File.exists?(skill_file), do: File.read!(skill_file), else: ""

    unless String.contains?(content, "name: #{tool.name}") do
      # Append to SKILL.md
      File.write!(skill_file, "\n" <> limited_entry, [:append])
      Logger.info("Appended new skill to #{skill_file}: #{tool.name}")
    else
      Logger.info("Skill #{tool.name} already exists in #{skill_file}, skipping.")
    end
  end
end
