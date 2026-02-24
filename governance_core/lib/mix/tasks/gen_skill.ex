defmodule Mix.Tasks.GenSkill do
  use Mix.Task

  @shortdoc "Generates a new SKILL.md file for an agent skill"

  def run(args) do
    if length(args) < 2 do
      Mix.raise "Usage: mix gen_skill <name> <description>"
    end

    [name | description_parts] = args
    description = Enum.join(description_parts, " ")

    create_skill(name, description)
  end

  defp create_skill(name, description) do
    # Normalize name to kebab-case
    normalized_name =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    # Locate .agent directory
    root_skills_dir =
      cond do
        File.exists?(".agent/skills") -> ".agent/skills"
        File.exists?("../.agent/skills") -> "../.agent/skills"
        true ->
          Mix.shell().info("Warning: .agent/skills directory not found. Creating in current directory.")
          "skills"
      end

    path = Path.join(root_skills_dir, normalized_name)
    filepath = Path.join(path, "SKILL.md")

    content = """
    ---
    name: #{name}
    description: #{description}
    version: 1.0.0
    ---

    # #{name}

    #{description}

    ## Usage

    Provide instructions on how to use this skill here.
    """

    if String.length(content) > 1024 do
      Mix.shell().info("Warning: Generated content exceeds 1024 characters standard.")
    end

    File.mkdir_p!(path)
    File.write!(filepath, content)

    Mix.shell().info("Created skill '#{name}' at #{filepath}")
  end
end
