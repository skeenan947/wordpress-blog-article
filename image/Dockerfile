FROM library/wordpress:6-php7.4-apache

USER root

RUN apt -q update && apt -qy install nfs-client nfs-server && apt clean
ADD ./init.sh .
ADD ./wp-config.php /var/www-local/core/wp-config.php

ENTRYPOINT ["./init.sh"]
