output "name" {
  description = "Repository name, taken from the created resource rather than the catalogue so that anything depending on it waits for the repository to exist."
  value       = github_repository.this.name
}

output "node_id" {
  value = github_repository.this.node_id
}

output "rulesets" {
  description = "Which rulesets this repository carries, for the drift report."
  value = compact([
    length(github_repository_ruleset.quality) > 0 ? "quality" : "",
    length(github_repository_ruleset.review) > 0 ? "review" : "",
  ])
}
