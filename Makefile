-include .env

.PHONY: test coverage

branchName ?= master
repo ?= lista-new-contracts
all: test coverage

test:
	mkdir -p src/contracts
	rm -rf src/*
	git clone -b ${branchName} https://github.com/lista-dao/${repo}.git src/${repo}
	mv src/${repo}/src/ src/contracts/
	find ./src -mindepth 1 -maxdepth 1 ! -name 'contracts' -exec rm -rf {} +
	find ./src/contracts -type f -exec sed -i '' 's/import \"hardhat\/console\.sol/\/\/ import \"hardhat\/console\.sol/g' {} +	
	find ./src/contracts -type f -exec sed -i '' 's/console/\/\/ console/g' {} +
	forge test

coverage:
	mkdir -p coverage
	forge coverage --report lcov
	lcov --remove lcov.info -o coverage/lcov.info --rc branch_coverage=1 --rc derive_function_end_line=0
	genhtml coverage/lcov.info -o coverage --rc branch_coverage=1 --rc derive_function_end_line=0 --ignore-errors inconsistent,category