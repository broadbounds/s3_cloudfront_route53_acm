################################################################################################################
## Creates a setup to serve a static website from an AWS S3 bucket, with a Cloudfront CDN and
## certificates from AWS Certificate Manager.
## 
## Tuto at https://github.com/cloudmaniac/terraform-aws-static-website
## Deploy remark:
##    Do not push files to the S3 bucket with an ACL giving public READ access, e.g s3-sync --acl-public
## Before we run terraform apply, we must: 
## - Setup an email redirect with our domain registrar to redirect “admin@your-domain” to an email inbox that we can receive email at.
## After we run terraform apply, we must:
## - Configure on our domain registrar settings, the AWS Route53 nameservers received 
##
## To use CloudFront with ACM certificates, the certificates must be requested in region us-east-1
################################################################################################################

# We set AWS as our default cloud provider
# By default, resources use a default provider configuration (one without an alias argument)
provider "aws" {
   region  = var.aws_region
   access_key = var.access_key
   secret_key = var.secret_key
 }

# We can set up multiple providers and use them for creating resources in different regions or in different AWS accounts by creating aliases.
# Some AWS services require the us-east-1 (N. Virginia) region to be configured:
# To use an ACM certificate with CloudFront, we must request or import the certificate in the US East (N. Virginia) region.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key 
}



## AWS Route53 is a DNS service used to perform three main functions: domain registration, DNS routing, and health checking.
# The first step to configure the DNS service for our domain is to create the public hosted zone
# the name server (NS) record, and the start of a zone of authority (SOA) record are automatically created by AWS
resource  "aws_route53_zone" "main" {
  name         = var.www-website-domain
}


# We use ACM (AWS Certificate Manager) to create the wildcard certificate *.<yourdomain.com>
# This resource won't be created until we receive the email verifying we own the domain and we click on the confirmation link.
resource "aws_acm_certificate" "wildcard_website" {
  # We refer to the aliased provider ( ${provider_name}.${alias} ) for creating our ACM resource. 
  provider                  = aws.us-east-1
  # We want a wildcard cert so we can host subdomains later.
  domain_name       = "*.${var.website-domain}" 
  # We also want the cert to be valid for the root domain even though we'll be redirecting to the www. domain immediately.
  subject_alternative_names = ["${var.website-domain}"]
  # Which method to use for validation. DNS or EMAIL are valid, NONE can be used for certificates that were imported into ACM and then into Terraform. 
  validation_method         = "EMAIL"

  # (Optional) A mapping of tags to assign to the resource. 
  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  # The lifecycle block is available for all resource blocks regardless of type
  # create_before_destroy(bool), prevent_destroy(bool), and ignore_changes(list of attribute names)
  # to be used when a resource is created with references to data that may change in the future, but should not affect said resource after its creation 
  lifecycle {
    ignore_changes = [tags["Changed"]]
  }

}


# This resource is simply a waiter for manual email approval of ACM certificates.
# We use the aws_acm_certificate_validation resource to wait for the newly created certificate to become valid
# and then use its outputs to associate the certificate Amazon Resource Name (ARN) with the CloudFront distribution
# The certificate Amazon Resource Name (ARN) provided by aws_acm_certificate looks identical, but is almost always going to be invalid right away. 
# Using the output from the validation resource ensures that Terraform will wait for ACM to validate the certificate before resolving its ARN.
resource "aws_acm_certificate_validation" "wildcard_cert" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.wildcard_website.arn
}


## Find a certificate that is issued
## Get the ARN of the issued certificate in AWS Certificate Manager (ACM)
data "aws_acm_certificate" "wildcard_website" {
  provider = aws.us-east-1

  # This argument is available for all resource blocks, regardless of resource type
  # Necessary when a resource or module relies on some other resource's behavior but doesn't access any of that resource's data in its arguments
  depends_on = [
    aws_acm_certificate.wildcard_website,
    aws_acm_certificate_validation.wildcard_cert,
  ]

  # (Required) The domain of the certificate to look up 
  domain      = "*.${var.website-domain}" #var.www-website-domain 
  # (Optional) A list of statuses on which to filter the returned list. Default is ISSUED if no value is specified
  # Valid values are PENDING_VALIDATION, ISSUED, INACTIVE, EXPIRED, VALIDATION_TIMED_OUT, REVOKED and FAILED 
  statuses    = ["ISSUED"]
  # Returning only the most recent one 
  most_recent = true
}

## S3
# Creates bucket to store logs
resource "aws_s3_bucket" "website_logs" {
  bucket = "${var.www-website-domain}-logs"
  acl    = "log-delivery-write"

  # Comment the following line if you are uncomfortable with Terraform destroying the bucket even if this one is not empty
  force_destroy = true


  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}

# Creates bucket to store the static website
resource "aws_s3_bucket" "website_root" {
  bucket = "${var.www-website-domain}"
  # Because we want our site to be available on the internet, we set this so anyone can read this bucket 
  acl    = "public-read"
   
  #policy = file("policy.json") 
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.www-website-domain}/*"]
    }
  ]
}
POLICY 

  # Comment the following line if you are uncomfortable with Terraform destroying the bucket even if not empty
  force_destroy = true

  logging {
    target_bucket = aws_s3_bucket.website_logs.bucket
    target_prefix = "${var.www-website-domain}/"
  }

  # For S3 to understand what it means to host a static website
  website {
    # (Required, unless using redirect_all_requests_to) Here we tell S3 what to use when a request comes in to the root ex. https://www.domain.com
    index_document = "index.html"
    # (Optional) The page to serve up if a request results in an error or a non-existing page
    error_document = "404.html"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}




// we upload our html files to s3 bucket
resource "aws_s3_bucket_object" "file_upload1" {
  bucket = "${aws_s3_bucket.website_root.bucket}"
  key    = "my-www-website-domain-bucket-key"
  source = "index.html"
} 
resource "aws_s3_bucket_object" "file_upload2" {
  bucket = "${aws_s3_bucket.website_redirect.bucket}"
  key    = "my-website-domain-bucket-key"
  source = "index.html"
}   

// we upload our html files to s3 bucket
resource "aws_s3_bucket_object" "file_upload11" {
  bucket = "${aws_s3_bucket.website_root.bucket}"
  key    = "my-www-website-domain-bucket-key"
  source = "404.html"
} 
resource "aws_s3_bucket_object" "file_upload12" {
  bucket = "${aws_s3_bucket.website_redirect.bucket}"
  key    = "my-website-domain-bucket-key"
  source = "404.html"
}   
   
   
## CloudFront
# Creates the CloudFront distribution to serve the static website
resource "aws_cloudfront_distribution" "website_cdn_root" {
  enabled     = true
  # (Optional) - The price class for this distribution. One of PriceClass_All, PriceClass_200, PriceClass_100 
  price_class = "PriceClass_All"
  # (Optional) - Extra CNAMEs (alternate domain names), if any, for this distribution 
  aliases = [var.www-website-domain]

  # Origin is where CloudFront gets its content from 
  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_root.id}"
    domain_name = aws_s3_bucket.website_root.website_endpoint

    custom_origin_config {
      # The protocol policy that you want CloudFront to use when fetching objects from the origin server (a.k.a S3 in our situation). 
      # HTTP Only is the default setting when the origin is an Amazon S3 static website hosting endpoint
      # This is because Amazon S3 doesn’t support HTTPS connections for static website hosting endpoints. 
      origin_protocol_policy = "http-only"
      http_port            = 80
      https_port           = 443
      origin_ssl_protocols = ["TLSv1.2", "TLSv1.1", "TLSv1"]
    }
  }

  default_root_object = "index.html"

  logging_config {
    bucket = aws_s3_bucket.website_logs.bucket_domain_name
    prefix = "${var.www-website-domain}/"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    # This needs to match the `origin_id` above 
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_root.id}"
    min_ttl          = "0"
    default_ttl      = "300"
    max_ttl          = "1200"

    # Redirects any HTTP request to HTTPS 
    viewer_protocol_policy = "redirect-to-https" 
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.wildcard_website.arn
    ssl_support_method  = "sni-only"
  }

  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 404
    response_page_path    = "/404.html"
    response_code         = 404
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [
      tags["Changed"],
      viewer_certificate,
    ]
  }
}


# Creates the DNS record to point on the main CloudFront distribution ID
resource "aws_route53_record" "website_cdn_root_record" {
  #zone_id = data.aws_route53_zone.wildcard_website.zone_id
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = var.www-website-domain
  type    = "A"

  alias {
    name = aws_cloudfront_distribution.website_cdn_root.domain_name
    zone_id = aws_cloudfront_distribution.website_cdn_root.hosted_zone_id
    evaluate_target_health = false
  }
}





################################################################################################################
## we need to create a whole new S3 bucket, CloudFront distribution and Route53 record just to redirect https://ourdomain to https://www.ourdomain
## That’s because although S3 can serve up a redirect to the www version of your site, it can’t host SSL certs and so you need CloudFront. 
################################################################################################################


# Creates the CloudFront distribution to serve the redirection website (if redirection is required)
resource "aws_cloudfront_distribution" "website_cdn_redirect" {
  enabled     = true
  price_class = "PriceClass_All"

  aliases = [var.website-domain]

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_redirect.id}"
    domain_name = aws_s3_bucket.website_redirect.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  logging_config {
    bucket = aws_s3_bucket.website_logs.bucket_domain_name
    prefix = "${var.www-website-domain}/"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_redirect.id}"
    min_ttl          = "0"
    default_ttl      = "300"
    max_ttl          = "1200"

    viewer_protocol_policy = "redirect-to-https" # Redirects any HTTP request to HTTPS
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.wildcard_website.arn
    ssl_support_method  = "sni-only"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [
      tags["Changed"],
      viewer_certificate,
    ]
  }
}

# Creates the DNS record to point on the CloudFront distribution ID that handles the redirection website
resource "aws_route53_record" "website_cdn_redirect_record" {
  #zone_id = data.aws_route53_zone.main.zone_id
  zone_id = "${aws_route53_zone.main.zone_id}"
  # NOTE: name is blank here.
  #name = "" 
  name    = var.website-domain
  type    = "A"

  alias {
    name = aws_cloudfront_distribution.website_cdn_redirect.domain_name
    zone_id = aws_cloudfront_distribution.website_cdn_redirect.hosted_zone_id
    evaluate_target_health = false
  }
   

}


# Creates bucket for the website handling the redirection (if required), e.g. from https://example.com to https://www.example.com 
resource "aws_s3_bucket" "website_redirect" {
  bucket        = "${var.website-domain}"
  acl           = "public-read"
  force_destroy = true
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.website-domain}/*"]
    }
  ]
}
POLICY 

  logging {
    target_bucket = aws_s3_bucket.website_logs.bucket
    target_prefix = "${var.www-website-domain}-redirect/"
  }

  website {
    # Note this redirect. Here's where the magic happens. 
    redirect_all_requests_to = "https://${var.www-website-domain}"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}

