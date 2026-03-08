defmodule Mix.Tasks.GenSkill do
  use Mix.Task
  require Logger

  @shortdoc "Generates or updates a SKILL.md entry with YAML frontmatter"

  @moduledoc """
  Generates or appends a skill entry to the SKILL.md documentation.

  Enforces a 1024-character limit per entry and uses standard YAML frontmatter.

  Usage:
      mix gen_skill "Skill Name" "Description"
  """

  @skill_file "SKILL.md"
  @max_chars 1024

  def run(args) do
    case args do
      [name, description] ->
        generate_skill(name, description)
      _ ->
        Mix.shell().error("Usage: mix gen_skill \"Skill Name\" \"Description\"")
    end
  end

  defp generate_skill(name, description) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    entry = """
    ---
    name: #{name}
    date: #{timestamp}
    ---

    # #{name}

    #{description}
    """

    if String.length(entry) > @max_chars do
      Mix.shell().error("Skill entry exceeds maximum allowed character length of #{@max_chars}.")
    else
      append_entry(entry)
    end
  end

  defp append_entry(entry) do
    File.write!(@skill_file, "\n#{entry}\n", [:append])
    Mix.shell().info("Appended skill to #{@skill_file}")
  end
end
