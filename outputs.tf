output "testing" {
  value = "Test this demo code by going to https://${aws_route53_record.myapp.fqdn} and checking your have a valid SSL cert"
}
output "testing_sclient" {
  value = "Test this SSL by using openssl s_client -host ${aws_route53_record.myapp.fqdn} -port 443 and looking at the certs"
}

output "s3_bucket_details" {
  value       = aws_s3_bucket.www
  description = "The details of the S3 bucket"
}

output "aws_cloudfront_details" {
  value       = aws_cloudfront_distribution.www_distribution
  description = "The details of the cloudfront"
}

output "aws_route53_details" {
  value       = aws_route53_zone.zone
  description = "The details of the route53"
}
