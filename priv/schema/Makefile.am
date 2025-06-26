## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

schema_DATA = $(abs_builddir)/resourceCatalogManagement.json \
		$(abs_builddir)/resourceActivationAndConfiguration.json \
		$(abs_builddir)/resourceInventoryManagement.json \
		$(abs_builddir)/Nrf_Rating.json \
		$(abs_builddir)/ECS_base.json \
		$(abs_builddir)/ECS_ecs.json \
		$(abs_builddir)/ECS_service.json \
		$(abs_builddir)/ECS_network.json \
		$(abs_builddir)/ECS_server.json \
		$(abs_builddir)/ECS_client.json \
		$(abs_builddir)/ECS_source.json \
		$(abs_builddir)/ECS_destination.json \
		$(abs_builddir)/ECS_url.json \
		$(abs_builddir)/ECS_user.json \
		$(abs_builddir)/ECS_related.json \
		$(abs_builddir)/ECS_http.json \
		$(abs_builddir)/ECS_event.json \
		$(abs_builddir)/ECS_3gpp_ro.json \
		$(abs_builddir)/ECS_3gpp_rf.json \
		$(abs_builddir)/ECS_prepaid.json \
		$(abs_builddir)/ECS_postpaid.json \
		$(abs_builddir)/ECS_rating.json


$(abs_builddir)/%.json: $(srcdir)/%.json
	if [ ! -e $@ ]; then \
		$(LN_S) $< $@; \
	fi

check_DATA = .validation_ok

.validation_ok:
	@if ajv help > /dev/null 2>&1; then \
		if ! ajv compile -s resourceCatalogManagement.json \
				--strict=false; \
				then exit 1; fi; \
		if ! ajv compile -s resourceActivationAndConfiguration.json \
				--strict=false; \
				then exit 1; fi; \
		if ! ajv compile -s resourceInventoryManagement.json \
				--strict=false; \
				then exit 1; fi; \
		if ! ajv compile -s Nrf_Rating.json \
				--strict=false; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_base.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_ecs.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_service.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_network.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_server.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_client.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_source.json \
				-r ECS_user.json \
				-r ECS_related.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_destination.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_url.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_user.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_related.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_http.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_event.json \
				--validate-formats=false \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_3gpp_ro.json \
				--validate-formats=false \
				-r ECS_base.json \
				-r ECS_ecs.json \
				-r ECS_server.json \
				-r ECS_client.json \
				-r ECS_network.json \
				-r ECS_service.json \
				-r ECS_source.json \
				-r ECS_user.json \
				-r ECS_related.json \
				-r ECS_destination.json \
				-r ECS_event.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_3gpp_rf.json \
				--validate-formats=false \
				-r ECS_base.json \
				-r ECS_ecs.json \
				-r ECS_server.json \
				-r ECS_client.json \
				-r ECS_network.json \
				-r ECS_service.json \
				-r ECS_source.json \
				-r ECS_user.json \
				-r ECS_related.json \
				-r ECS_destination.json \
				-r ECS_event.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_prepaid.json \
				--validate-formats=false \
				-r ECS_base.json \
				-r ECS_ecs.json \
				-r ECS_service.json \
				-r ECS_network.json \
				-r ECS_user.json \
				-r ECS_event.json \
				-r ECS_url.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_postpaid.json \
				--validate-formats=false \
				-r ECS_base.json \
				-r ECS_ecs.json \
				-r ECS_service.json \
				-r ECS_network.json \
				-r ECS_user.json \
				-r ECS_event.json \
				--spec=draft2020; \
				then exit 1; fi; \
		if ! ajv compile -s ECS_rating.json \
				--validate-formats=false \
				-r ECS_base.json \
				-r ECS_ecs.json \
				-r ECS_service.json \
				-r ECS_network.json \
				-r ECS_user.json \
				-r ECS_event.json \
				-r ECS_url.json \
				-r ECS_http.json \
				--spec=draft2020; \
				then exit 1; fi; \
	else \
		echo "WARNING: ajv-cli needed to validate JSON Schema"; \
	fi

