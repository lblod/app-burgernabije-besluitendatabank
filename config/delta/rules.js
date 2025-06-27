export default [
    ...["http://data.vlaanderen.be/ns/besluit#Agendapunt",
        "http://data.vlaanderen.be/ns/besluit#Besluit",
        "http://data.vlaanderen.be/ns/besluit#Bestuursorgaan",
        "http://data.vlaanderen.be/ns/besluit#BehandelingVanAgendapunt",
        "http://data.vlaanderen.be/ns/besluit#Zitting",
        "http://data.vlaanderen.be/ns/besluit#Stemming",
        "http://data.europa.eu/m8g/Requirement",
        "http://data.europa.eu/m8g/EvidenceType",
        "http://data.europa.eu/m8g/EvidenceTypeList",
        "https://data.vlaanderen.be/ns/mobiliteit-intelligente-toegang#Voorwaardecollectie",
        "http://purl.org/vocab/cpsv#PublicService",
        "https://data.vlaanderen.be/ns/mobiliteit#Zone",
        "http://www.w3.org/ns/locn#Geometry",
        "http://www.w3.org/ns/locn#Location",
        "http://www.w3.org/ns/locn#Adres",
        "https://data.vlaanderen.be/ns/generiek/#GeografischePositie",
        "http://xmlns.com/foaf/0.1/Document"
    ].map((type) => ({
        match: {
            predicate: {
                type: 'uri',
                value: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
            },
            object: {
                type: 'uri',
                value: type
            }
        },
        callback: {
            url: 'http://uuid-generation/delta',
            method: 'POST'
        },
        options: {
            resourceFormat: 'v0.0.1',
            gracePeriod: 250,
            ignoreFromSelf: false
        }
    })),
    {
        match: {
            predicate: {
                type: 'uri',
                value: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
            },
            object: {
                type: 'uri',
                value: "http://data.vlaanderen.be/ns/besluit#Agendapunt",

            }
        },
        callback: {
            url: 'http://search/update',
            method: 'POST'
        },
        options: {
            resourceFormat: "v0.0.1",
            gracePeriod: 10000,
            ignoreFromSelf: true
        }
    },
    // NOTE:
    // Deliberate disabling of delta-notifications for resources
    // Under heavy load; resources has issues clearing cache
    // This means we can't use mu-cache ATM.
    // Please; check dispatcher for more info
    // {
    //     match: {
    //         subject: {}
    //     },
    //     callback: {
    //         url: "http://resources/.mu/delta",
    //         method: "POST"
    //     },
    //     options: {
    //         resourceFormat: "v0.0.1",
    //         gracePeriod: 250,
    //         ignoreFromSelf: true
    //     }
    // }
];
