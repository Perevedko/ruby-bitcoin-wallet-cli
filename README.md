Usages

```shell
# First, build it
docker-compose build

# Generate new private key
docker-compose run --rm wallet generate

# Check balance
docker-compose run --rm wallet balance

# Send funds
docker-compose run --rm wallet send [address] [amount]
```