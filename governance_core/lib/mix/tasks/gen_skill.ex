defmodule Mix.Tasks.GenSkill do
  use Mix.Task

  @shortdoc "Generates or updates a SKILL.md file with YAML frontmatter"

  @moduledoc """
  Generates or updates a SKILL.md documentation file.
  Ensures that the content adheres to a 1024-character limit and has YAML frontmatter.

  Usage:
      mix gen_skill <tool_name> <description>
  """

  @max_length 1024

  @impl Mix.Task
  def run([tool_name | description_words]) do
    description = Enum.join(description_words, " ")

    content = """
    ---
    name: #{tool_name}
    version: 1.0.0
    ---
    # #{tool_name}

    #{description}
    """

    if String.length(content) > @max_length do
      Mix.raise("Error: SKILL.md content exceeds the #{@max_length}-character limit (currently #{String.length(content)} characters).")
    end

    file_path = "SKILL.md"

    # Append to the file rather than overwriting it, separating entries with newlines
    File.write!(file_path, "\n" <> content, [:append])
    Mix.shell().info("Appended tool '#{tool_name}' to #{file_path} successfully.")
  end

  def run(_) do
    Mix.raise("Usage: mix gen_skill <tool_name> <description>")
  end
end
