defmodule GovernanceCore.Repo.Migrations.AlterAgentsAddMvpFields do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add(:type, :string, default: "picoclaw", null: false)
      add(:soul, :map)
      add(:skills, {:array, :string}, default: [], null: false)
      add(:category, :string)
      add(:description, :text)
      add(:protocol, :string, default: "ABL.ONE/1.0", null: false)

      add(:daily_token_limit, :integer, default: 100_000)
      add(:tokens_used_today, :integer, default: 0)
      add(:memory_limit_mb, :integer, default: 128)
      add(:cpu_limit, :float, default: 0.5)

      add(:price_monthly, :integer, default: 0)
      add(:owner, :string, default: "anonymous", null: false)
    end

    create(index(:agents, [:type]))
    create(index(:agents, [:owner]))
  end
end
