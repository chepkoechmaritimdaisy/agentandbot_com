defmodule GovernanceCore.Repo.Migrations.RenameAgentsToPersonas do
  use Ecto.Migration

  def change do
    # 1. Rename the table
    rename table(:agents), to: table(:personas)

    # 2. Add Unified Swarm fields
    alter table(:personas) do
      add :sub_type, :string, default: "bot", null: false # bot, human
      add :access_group, :string, default: "external", null: false # internal, external
      add :balance_cents, :integer, default: 0, null: false
      add :metadata, :map, default: %{}
    end

    # 3. Update indices
    drop index(:personas, [:type])
    drop index(:personas, [:owner])
    
    create index(:personas, [:sub_type])
    create index(:personas, [:access_group])
    create index(:personas, [:owner])
  end
end
