import re

import httpx

from .wallet import WalletError


def catalog_items(data, catalog):
    aggregated = {}
    for item in data.get("items", []):
        price = item.get("price", {}).get("id")
        if price not in catalog:
            raise WalletError("Unrecognized Paddle price", 422)
        definition = catalog[price]
        sku, quantity = definition["sku"], item.get("quantity", 1)
        if not isinstance(quantity, int) or not 1 <= quantity <= 1000:
            raise WalletError("Invalid purchase quantity", 422)
        allowed = {"base": 3, "credits.5": 5, "credits.15": 15, "credits.40": 40, "accessory.hat": 0, "accessory.glasses": 0}
        if sku not in allowed or (sku == "base" and quantity != 1):
            raise WalletError("Invalid SKU configuration", 422)
        if sku not in aggregated:
            aggregated[sku] = {"sku": sku, "credits": allowed[sku], "quantity": 0}
        aggregated[sku]["quantity"] += quantity
    if not aggregated:
        raise WalletError("Purchase has no items", 422)
    return list(aggregated.values())


async def customer_email(settings, customer_id):
    if not re.fullmatch(r"ctm_[a-z0-9]{26}", customer_id or ""):
        raise WalletError("Invalid Paddle customer", 422)
    if not settings.paddle_api_key:
        raise WalletError("Paddle API is not configured", 503)
    host = "https://api.paddle.com" if settings.paddle_environment == "production" else "https://sandbox-api.paddle.com"
    async with httpx.AsyncClient(timeout=3, follow_redirects=False) as client:
        response = await client.get(f"{host}/customers/{customer_id}", headers={"Authorization": f"Bearer {settings.paddle_api_key}"})
        if response.status_code != 200:
            raise WalletError("Could not verify the purchase customer", 503)
        return response.json()["data"]["email"].strip().lower()
