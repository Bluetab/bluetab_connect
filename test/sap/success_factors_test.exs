defmodule BluetabConnect.Sap.SuccessFactorsTest do
  use ExUnit.Case, async: true

  alias BluetabConnect.Sap.SuccessFactors

  describe "decode_odata_response/1" do
    test "returns results list for a collection payload" do
      response = %{
        status: 200,
        body: %{
          "d" => %{
            "results" => [
              %{"externalCode" => "ESP", "holidayClass" => "STANDARD"}
            ]
          }
        }
      }

      assert {:ok, [%{"externalCode" => "ESP"}]} = SuccessFactors.decode_odata_response(response)
    end

    test "returns page tuple when __next is present" do
      response = %{
        status: 200,
        body: %{
          "d" => %{
            "results" => [%{"externalCode" => "ESP"}],
            "__next" => "https://example.com/odata/v2/HolidayCalendar?$skiptoken=1"
          }
        }
      }

      assert {:ok, {:page, [%{"externalCode" => "ESP"}], next_url}} =
               SuccessFactors.decode_odata_response(response)

      assert String.contains?(next_url, "skiptoken=1")
    end

    test "returns error when body has no d key" do
      response = %{status: 200, body: %{"error" => %{"message" => "Unauthorized"}}}

      assert {:error, {:unexpected_odata_payload, summary}} =
               SuccessFactors.decode_odata_response(response)

      assert is_binary(summary)
      assert String.contains?(summary, "error")
    end

    test "returns error when d has no results list" do
      response = %{
        status: 200,
        body: %{"d" => %{"externalCode" => "ESP", "holidayClass" => "STANDARD"}}
      }

      assert {:error, {:unexpected_odata_payload, summary}} =
               SuccessFactors.decode_odata_response(response)

      assert is_binary(summary)
      assert String.contains?(summary, "externalCode")
    end

    test "returns http_error for non-2xx responses" do
      response = %{status: 401, body: %{"error" => "denied"}}

      assert {:error, {:http_error, 401, summary}} =
               SuccessFactors.decode_odata_response(response)

      assert is_binary(summary)
    end
  end

  describe "parse_holiday_calendars/1" do
    test "parses nested holiday assignments and odata dates" do
      calendars = [
        %{
          "externalCode" => "ESP",
          "holidayClass" => "STANDARD",
          "holidayAssignments" => %{
            "results" => [
              %{
                "date" => "/Date(1704067200000)/",
                "holiday" => "NEW_YEAR",
                "holidayNav" => %{"name_defaultValue" => "New Year"}
              }
            ]
          }
        }
      ]

      assert {:ok, [calendar]} = SuccessFactors.parse_holiday_calendars(calendars)

      assert calendar.code == "ESP"
      assert calendar.class == "STANDARD"
      assert [holiday] = calendar.holidays
      assert holiday.holiday_code == "NEW_YEAR"
      assert holiday.name == "New Year"
      assert holiday.date == ~D[2024-01-01]
    end

    test "returns explicit error for non-list payloads" do
      assert {:error, {:invalid_holiday_calendars_payload, summary}} =
               SuccessFactors.parse_holiday_calendars(%{body: %{"error" => true}})

      assert is_binary(summary)
    end
  end
end
