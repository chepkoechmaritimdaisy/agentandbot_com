defmodule Mix.Tasks.GenSkill do
  @moduledoc """
  Generates or updates the SKILL.md documentation for a new tool or function.
  Enforces YAML frontmatter and a 1024-character limit per entry.

  Usage:
      mix gen_skill "Tool Name" "Description of the tool within 1024 chars"
  """
  use Mix.Task

  @shortdoc "Generates SKILL.md entry for a tool"

  @skill_file "SKILL.md"

  @impl Mix.Task
  def run(args) do
    case args do
      [name, description] ->
        if String.length(description) > 1024 do
          Mix.shell().error("Error: Description exceeds the 1024-character limit.")
        else
          append_skill(name, description)
          Mix.shell().info("Successfully added entry for '#{name}' to #{@skill_file}.")
        end
      _ ->
        Mix.shell().error("Usage: mix gen_skill \"Tool Name\" \"Description\"")
    end
  end

  defp append_skill(name, description) do
    date = Date.to_string(Date.utc_today())

    entry = """
    ---
    name: "#{name}"
    date: #{date}
    ---
    #{description}

    """

    # We assume SKILL.md is at the root of the project
    File.write!(@skill_file, entry, [:append])
  end
end
