# PHP runtime for the reference WordPress 7.2-alpha oracle.
# The repo is mounted at /workspace/WordPress because tools/*.php hardcode that path.
FROM php:8.3-cli

RUN docker-php-ext-install mysqli

WORKDIR /workspace/WordPress/_reversa_forward/oracle/wordpress

EXPOSE 8099
CMD ["php", "-S", "0.0.0.0:8099", "-t", ".", "router.php"]
