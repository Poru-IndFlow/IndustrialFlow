class_name BehaviourFactory
extends RefCounted


static func create(processing_mode: String) -> MachineBehaviour:
	match processing_mode:
		"supplier":
			return SupplierBehaviour.new()
		"continuous":
			return ContinuousBehaviour.new()
		"storage":
			return StorageBehaviour.new()
		_:
			push_warning(
				"Unknown processing mode '%s'; using storage behaviour."
				% processing_mode
			)
			return StorageBehaviour.new()