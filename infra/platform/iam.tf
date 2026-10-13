data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# 1. Role for the EC2 lab host
#    - Session Manager access (admin shell without SSH)
#    - pull images from the supportflow ECR repo only
#    - read/write the backup bucket only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "host" {
  name = "supportflow-host"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "host_least_privilege" {
  name = "supportflow-host-ecr-pull-and-backups"
  role = aws_iam_role.host.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*" # this action does not support resource scoping
      },
      {
        Sid    = "EcrPullAppRepoOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "BackupsBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.backups.arn
      },
      {
        Sid      = "BackupsBucketObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "supportflow-host"
  role = aws_iam_role.host.name
}

# ---------------------------------------------------------------------------
# 2. GitHub Actions -> AWS with OIDC (no stored AWS keys in GitHub)
#    Only pushes to the main branch of this one repo can assume the role,
#    and the role can only push to the supportflow ECR repo.
#    Pull requests cannot assume it (their token "sub" is different).
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_ecr_push" {
  name = "supportflow-github-ecr-push"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "supportflow-ecr-push-only"
  role = aws_iam_role.github_ecr_push.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushAppRepoOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
        ]
        Resource = aws_ecr_repository.app.arn
      },
    ]
  })
}
