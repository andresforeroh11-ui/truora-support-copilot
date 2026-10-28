-- La detección de incidentes solo cuenta tickets reales (excluye el set de evaluación).
create or replace view v_clasificaciones_vivas with (security_invoker = true) as
select c.* from clasificaciones c join tickets t on t.id = c.ticket_id
where not t.es_set_prueba;
