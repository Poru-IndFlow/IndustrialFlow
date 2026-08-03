class_name EventBus
extends RefCounted


signal machine_added(machine)
signal machine_removed(machine_id)
signal connection_added(connection)
signal connection_removed(connection)
signal connection_flow_changed(connection)
signal connection_settings_changed(connection)
signal machine_state_changed(machine)
signal machine_inventory_changed(machine)
signal machine_production_changed(machine)
signal machine_settings_changed(machine)
signal machine_performance_changed(machine)
signal machine_power_changed(machine)
signal machine_control_changed(machine)
signal machine_condition_changed(machine)
signal economy_changed(factory)
signal research_changed(factory)
signal machine_upgrades_changed(machine)
signal machine_maintenance_changed(machine)
signal production_targets_changed(factory)
signal customer_orders_changed(factory)
