defmodule BluetabConnect.Sap.Soap.ProyectosTest do
  use ExUnit.Case, async: true

  alias BluetabConnect.Sap.Soap.Proyectos

  defp imputacion(extra) do
    {:Imputacion,
     Map.merge(
       %{
         Code: "0000S87E",
         Estado: "Aprobado",
         IdProyecto: "1772",
         Horas: "8",
         IdTipoHora: "NORMAL",
         Comentario: "httpsjirabluetabnetbrowseHOR3746",
         MotivoRechazo: %{}
       },
       extra
     )}
  end

  describe "parse_imputacion/1" do
    test "returns the precontrato when SAP carries one" do
      assert %{precontrato: "PCW-751", code: "0000S87E"} =
               Proyectos.parse_imputacion(imputacion(%{Precontrato: "PCW-751"}))
    end

    test "trims the precontrato" do
      assert %{precontrato: "PCW-751"} =
               Proyectos.parse_imputacion(imputacion(%{Precontrato: " PCW-751 "}))
    end

    test "returns nil for the empty element SAP sends when there is no precontrato" do
      assert %{precontrato: nil} = Proyectos.parse_imputacion(imputacion(%{Precontrato: %{}}))
    end

    test "returns nil for a blank string" do
      assert %{precontrato: nil} = Proyectos.parse_imputacion(imputacion(%{Precontrato: "  "}))
    end

    test "returns nil when the field is absent" do
      assert %{precontrato: nil} = Proyectos.parse_imputacion(imputacion(%{}))
    end

    test "keeps the fields it already returned" do
      assert %{
               status: "Aprobado",
               project_id: "1772",
               hours: "8",
               type_id: "NORMAL",
               comment: "httpsjirabluetabnetbrowseHOR3746",
               reject_reason: %{}
             } = Proyectos.parse_imputacion(imputacion(%{}))
    end
  end
end
