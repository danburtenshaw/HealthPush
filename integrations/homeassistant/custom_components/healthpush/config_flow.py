"""Config flow for the HealthPush integration."""

from __future__ import annotations

import logging
from typing import Any

import voluptuous as vol

from homeassistant.components.webhook import async_generate_url
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.helpers import config_validation as cv

from .const import CONF_WEBHOOK_SECRET, DOMAIN

_LOGGER = logging.getLogger(__name__)


class HealthPushConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle a config flow for HealthPush."""

    VERSION = 1

    def __init__(self) -> None:
        """Initialise the config flow."""
        self._name: str = ""
        self._webhook_secret: str = ""
        self._webhook_id: str = ""

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Handle the initial user configuration step."""
        errors: dict[str, str] = {}

        if user_input is not None:
            self._name = user_input["name"]
            self._webhook_secret = user_input.get(CONF_WEBHOOK_SECRET, "")

            # Use a stable webhook id derived from the entry name so that
            # re-adding the same device always produces the same URL.
            self._webhook_id = f"{DOMAIN}_{cv.slugify(self._name)}"

            # Prevent duplicate entries for the same webhook id.
            await self.async_set_unique_id(self._webhook_id)
            self._abort_if_unique_id_configured()

            return await self.async_step_webhook_info()

        schema = vol.Schema(
            {
                vol.Required("name", default="iPhone"): str,
                vol.Optional(CONF_WEBHOOK_SECRET, default=""): str,
            }
        )

        return self.async_show_form(
            step_id="user",
            data_schema=schema,
            errors=errors,
        )

    async def async_step_webhook_info(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Show the generated webhook URL and finish setup."""
        if user_input is not None:
            # User clicked submit on the info page -- create the entry.
            return self.async_create_entry(
                title=self._name,
                data={
                    "name": self._name,
                    "webhook_id": self._webhook_id,
                    CONF_WEBHOOK_SECRET: self._webhook_secret,
                },
            )

        webhook_url = async_generate_url(self.hass, self._webhook_id)

        return self.async_show_form(
            step_id="webhook_info",
            description_placeholders={"webhook_url": webhook_url},
            data_schema=vol.Schema({}),
        )
