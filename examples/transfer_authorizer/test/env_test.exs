defmodule TransferAuthorizer.EnvTest do
  use ExUnit.Case, async: false

  alias TransferAuthorizer.Env

  @moduletag :tmp_dir

  setup do
    on_exit(fn ->
      for name <- ~w(TA_ENV_TEST_A TA_ENV_TEST_B TA_ENV_TEST_C), do: System.delete_env(name)
    end)
  end

  test "loads KEY=value lines over what is already set", %{tmp_dir: dir} do
    path = Path.join(dir, ".env")
    System.put_env("TA_ENV_TEST_A", "stale")

    File.write!(path, """
    # a comment

    TA_ENV_TEST_A=fresh
    TA_ENV_TEST_B="quoted=value"
    TA_ENV_TEST_C=
    """)

    assert Env.overload(path) == :ok
    assert System.get_env("TA_ENV_TEST_A") == "fresh"
    assert System.get_env("TA_ENV_TEST_B") == "quoted=value"
    assert System.get_env("TA_ENV_TEST_C") == ""
  end

  test "drops only a matching pair of surrounding quotes", %{tmp_dir: dir} do
    path = Path.join(dir, ".env")

    File.write!(path, """
    TA_ENV_TEST_A=token'
    TA_ENV_TEST_B='single'
    TA_ENV_TEST_C="mixed'
    """)

    Env.overload(path)

    assert System.get_env("TA_ENV_TEST_A") == "token'"
    assert System.get_env("TA_ENV_TEST_B") == "single"
    assert System.get_env("TA_ENV_TEST_C") == "\"mixed'"
  end

  test "raises naming the file when it cannot be read", %{tmp_dir: dir} do
    # A directory named .env reads as :eisdir.
    path = Path.join(dir, ".env")
    File.mkdir!(path)

    assert_raise File.Error, ~r/\.env/, fn -> Env.overload(path) end
  end

  test "does nothing without a .env file", %{tmp_dir: dir} do
    assert Env.overload(Path.join(dir, ".env")) == :ok
  end
end
