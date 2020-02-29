defmodule Definject do
  @uninjectable [:erlang, Kernel, Macro, Module, Access]
  alias Definject.Impl

  @doc """
  `definject` transforms a function to accept a map where dependent functions can be injected.

      import Definject

      definject send_welcome_email(user_id) do
        %{email: email} = Repo.get(User, user_id)

        Email.welcome(email)
        |> Mailer.send()
      end

  is expanded into

      def send_welcome_email(user_id, deps \\\\ %{}) do
        %{email: email} = (deps[{Repo, :get, 2}] || &Repo.get/2).(User, user_id)

        (deps[{Email, :welcome, 1}] || &Email.welcome/1).(email)
        |> (deps[{Mailer, :send, 1}] || &Mailer.send/1).()
      end

  Then we can inject mock functions in tests.

      test "send_welcome_email" do
        Accounts.send_welcome_email(100, %{
          {Repo, :get, 2} => fn User, 100 -> %User{email: "mr.jechol@gmail.com"} end,
          {Mailer, :send, 1} => fn %Email{to: "mr.jechol@gmail.com", subject: "Welcome"} ->
            Process.send(self(), :email_sent)
          end
        })

        assert_receive :email_sent
      end

  `definject` raises if the passed map includes a function that's not called within the injected function.
  You can disable this by adding `strict: false` option.

      test "send_welcome_email with strict: false" do
        Accounts.send_welcome_email(100, %{
          {Repo, :get, 2} => fn User, 100 -> %User{email: "mr.jechol@gmail.com"} end,
          {Repo, :all, 1} => fn _ -> [%User{email: "mr.jechol@gmail.com"}] end, # Unused
          :strict => false,
        })
      end
  """
  defmacro definject(head, do: body) do
    if Application.get_env(:definject, :enabled?, Mix.env() == :test) do
      Impl.inject_function(%{head: head, body: body, env: __CALLER__})
    else
      quote do
        def unquote(head), do: unquote(body)
      end
    end
  end

  @doc """
  If you don't need pattern matching in mock function, `mock/1` can be used to reduce boilerplates.

      test "send_welcome_email with mock/1" do
        Accounts.send_welcome_email(
          100,
          mock(%{
            &Repo.get/2 => %User{email: "mr.jechol@gmail.com"},
            &Mailer.send/1 => Process.send(self(), :email_sent)
          })
        )

        assert_receive :email_sent
      end

  Note that `Process.send(self(), :email_sent)` is surrounded by `fn _ -> end` when expanded.
  """
  defmacro mock({:%{}, _, mocks}) do
    mocks =
      mocks
      |> Enum.map(fn {k, v} ->
        {:&, _, [capture]} = k
        {:/, _, [mf, a]} = capture
        {mf, _, []} = mf
        {:., _, [m, f]} = mf

        quote do
          {{unquote(m), unquote(f), unquote(a)},
           unquote(__MODULE__).make_const_function(unquote(a), unquote(v), unquote(__CALLER__))}
        end
      end)

    {:%{}, [], mocks}
  end

  @doc false
  defmacro make_const_function(arity, expr, %Macro.Env{module: context}) do
    {:fn, [], [{:->, [], [Macro.generate_arguments(arity, context), expr]}]}
  end
end