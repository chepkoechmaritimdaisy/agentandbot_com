defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Auto-detects new functions/tools added in Elixir.GovernanceCore and creates
  or updates SKILL.md using a specific YAML format (1024 char limit).
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @skill_file "SKILL.md"
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    update_skills()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp update_skills do
    Logger.info("Updating SKILL.md...")

    skills = get_skills()
    yaml_content = generate_yaml(skills)

    File.write!(@skill_file, yaml_content)
    Logger.info("SKILL.md updated successfully.")
  end

  defp get_skills do
    Code.all_loaded()
    |> Enum.filter(fn {mod, _file} ->
      String.starts_with?(to_string(mod), "Elixir.GovernanceCore")
    end)
    |> Enum.flat_map(fn {mod, _file} ->
      extract_docs(mod)
    end)
  end

  defp extract_docs(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, _, _, docs} ->
        Enum.map(docs, fn
          {{:function, name, arity}, _anno, _signature, doc, _meta} ->
            doc_str =
              case doc do
                %{"en" => d} -> d
                :none -> "No documentation"
                _ -> "Unknown documentation"
              end

            %{
              module: inspect(mod),
              function: "#{name}/#{arity}",
              description: doc_str
            }

          _ ->
            nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp generate_yaml(skills) do
    header = "---\ntitle: GovernanceCore Skills\n---\n"

    body =
      skills
      |> Enum.map(fn skill ->
        desc = String.replace(skill.description, "\n", "\n    ")
        """
        - module: #{skill.module}
          function: #{skill.function}
          description: |
            #{desc}
        """
      end)
      |> Enum.join("")

    content = header <> body

    if String.length(content) > @max_chars do
      String.slice(content, 0, @max_chars)
    else
      content
    end
  end
end
