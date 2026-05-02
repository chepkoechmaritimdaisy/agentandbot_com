defmodule GovernanceCore.Monitoring.SkillTrackerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  setup do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.rm_rf!(priv_dir)
    File.mkdir_p!(priv_dir)

    on_exit(fn ->
      File.rm_rf!(priv_dir)
    end)

    :ok
  end

  test "generate_skills_docs chunks files and writes YAML properly" do
    # We'll just run it with whatever modules are loaded and verify the files
    capture_log(fn ->
      GovernanceCore.Monitoring.SkillTracker.generate_skills_docs()
    end)

    priv_dir = Path.join(File.cwd!(), "priv")

    assert File.exists?(Path.join(priv_dir, "SKILL.md"))

    # Read the file to ensure YAML syntax and indentation are present
    content = File.read!(Path.join(priv_dir, "SKILL.md"))
    assert content =~ "---"
    assert content =~ "skills:"
    assert content =~ "- name:"
    assert content =~ "description: |"
    assert content =~ "    " # Checking for indented descriptions
  end
end
