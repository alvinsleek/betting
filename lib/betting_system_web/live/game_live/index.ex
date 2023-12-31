defmodule BettingSystemWeb.GameLive.Index do
  use BettingSystemWeb, :live_view

  alias BettingSystem.Games
  alias BettingSystem.Games.Game
  alias BettingSystem.Accounts
  alias BettingSystem.Sports
  alias BettingSystem.Betslips
  alias BettingSystem.Bet
  alias BettingSystem.Bet.Bets

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    sports = Sports.list_sports(user.id)
    selected_bets = Betslips.get_betslips(user.id)
    changeset = Bet.change_bets(%Bets{})

    {:ok,
     socket
     |> assign(:games, list_games())
     |> assign(:user, user)
     |> assign(:sports, sports)
     |> assign(:bets, "")
     |> assign(:total_odds, 0.0)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Game")
    |> assign(:game, Games.get_game!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Game")
    |> assign(:game, %Game{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Games")
    |> assign(:game, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    game = Games.get_game!(id)
    {:ok, _} = Games.delete_game(game)

    {:noreply, assign(socket, :games, list_games())}
  end

  def handle_event(
        "add bet",
        %{"odds" => odds, "id" => game_id, "type" => type, "value" => ""},
        socket
      ) do
    is_betslip = Betslips.check_betslip!(socket.assigns.user.id, game_id)

    if is_nil(is_betslip) do
      game_id = String.to_integer(game_id)
      game_odds = String.to_float(odds)
      user_id = socket.assigns.user.id

      betslip_params = %{
        "user_id" => user_id,
        "game_id" => game_id,
        "odds" => game_odds,
        "status" => "in_betslip",
        "result_type" => type
      }

      case Betslips.create_betslip(betslip_params) do
        {:ok, _betslip} ->
          selected_bets = Betslips.get_betslips(socket.assigns.user.id)

          {:noreply,
           socket
           |> put_flash(:info, "Betslip created successfully")
           |> assign(:bets, selected_bets)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, changeset: changeset)}
      end
    else
      game_id = String.to_integer(game_id)
      game_odds = String.to_float(odds)
      user_id = socket.assigns.user.id

      betslip = Betslips.check_betslip!(socket.assigns.user.id, game_id)

      betslip_params = %{
        "user_id" => user_id,
        "game_id" => game_id,
        "odds" => game_odds,
        "status" => "in_betslip",
        "result_type" => type
      }

      case Betslips.update_betslip(betslip, betslip_params) do
        {:ok, _betslip} ->
          selected_bets = Betslips.get_betslips(socket.assigns.user.id)
          IO.inspect(selected_bets)

          {:noreply,
           socket
           |> put_flash(:info, "Betslip updated successfully")
           |> assign(:bets, selected_bets)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    end
  end

  def handle_event("cancel", %{"cancel" => id}, socket) do
    betslip_id = String.to_integer(id)
    betslip = Betslips.get_betslip!(betslip_id)
    {:ok, _} = Betslips.delete_betslip(betslip)

    {:noreply,
     socket
     |> assign(:bets, Betslips.get_betslips(socket.assigns.user.id))}
  end

  #   def handle_event("validate_amount", %{"bets" => bets_params}, socket) do
  # IO.inspect(bets_params)

  #     changeset =
  #       socket.assigns.bets
  #       |> Bet.change_bets(bets_params["amount"])
  #       |> Map.put(:action, :validate)

  #     {:noreply, assign(socket, :changeset, changeset)}
  #   end

  def handle_event("place bet", %{"bets" => %{"amount" => amount, "odds" => odds}}, socket) do
    amount = String.to_integer(amount)
    odds = String.to_float(odds)
    betslip_items = Betslips.get_betslips(socket.assigns.user.id)

    bet_slip_ids_map =
      Enum.map(betslip_items, fn betslip -> {betslip.game_id, betslip.game_id} end) |> Map.new()

    # bet_slip_ids_list =
    # Enum.map(betslip_items, fn betslip -> betslip.game_id end)
    unique_bet_id =
      SecureRandom.base64(socket.assigns.user.id)
      |> String.replace("==", "")
      |> String.replace("=", "")
      |> String.replace("/", "mbash")

    timestamp = DateTime.utc_now() |> DateTime.to_unix(:second) |> Integer.to_string()

    unique_bet_id = unique_bet_id <> timestamp

    IO.write("we got here")
    IO.inspect(bet_slip_ids_map)

    payout = amount * odds

    bet_params = %{
      "amount" => amount,
      "odds" => odds,
      "payout" => payout,
      "status" => "open",
      "bet_items" => bet_slip_ids_map,
      "bet_id" => unique_bet_id,
      "user_id" => socket.assigns.user.id
    }

    IO.inspect(bet_params)

    case Bet.create_bets(bet_params) do
      {:ok, _bets} ->
        for betslips <- betslip_items do
          Betslips.update_betslip(betslips, %{"status" => "out_of_slip"})
        end

        selected_bets = Betslips.get_betslips(socket.assigns.user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Bets created successfully")
         |> assign(:bets, selected_bets)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp list_games do
    Games.list_games()
    |> Enum.filter(fn x -> x.status == "pending" end)
  end
end
