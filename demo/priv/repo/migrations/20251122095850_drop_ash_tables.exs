defmodule Demo.Repo.Migrations.DropAshTables do
  @moduledoc """
  Drops Ash-related tables and functions.

  Ash support has been moved to a community project: https://github.com/enoonan/ash_backpex
  """

  use Ecto.Migration

  def up do
    # Drop tickets table
    drop_if_exists table(:tickets)

    # Drop Ash functions
    execute("""
    DROP FUNCTION IF EXISTS ash_raise_error(jsonb);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_raise_error(jsonb, ANYCOMPATIBLE);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_elixir_and(BOOLEAN, ANYCOMPATIBLE);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_elixir_and(ANYCOMPATIBLE, ANYCOMPATIBLE);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_elixir_or(ANYCOMPATIBLE, ANYCOMPATIBLE);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_elixir_or(BOOLEAN, ANYCOMPATIBLE);
    """)

    execute("""
    DROP FUNCTION IF EXISTS ash_trim_whitespace(text[]);
    """)
  end
end
