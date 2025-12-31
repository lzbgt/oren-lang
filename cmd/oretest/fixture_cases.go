package main

func buildFixtureCases(target string, gcArg string, full bool) []fixtureCase {
	if full {
		return buildFixtureCasesFull(target, gcArg)
	}
	return buildFixtureCasesFast(target, gcArg)
}
