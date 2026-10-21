variable "repo" {
  description = "One decoded file from repos/. Shape is enforced by schema/repo.schema.json before this ever runs."
  type        = any
}

variable "base_labels" {
  type    = any
  default = []
}

variable "extra_labels" {
  type    = any
  default = []
}
