package com.polyp.polypweb.config;

import com.polyp.polypweb.document.UserAccount;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.stereotype.Component;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class UserAccountIndexInitializer implements ApplicationRunner {

    private final MongoTemplate mongoTemplate;

    public UserAccountIndexInitializer(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    @Override
    public void run(ApplicationArguments args) {
        mongoTemplate.indexOps(UserAccount.class)
                .createIndex(new Index().on("email", Sort.Direction.ASC).unique());
    }
}
