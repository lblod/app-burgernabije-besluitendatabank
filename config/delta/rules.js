const interestingTypes = /^http:\/\/data\.vlaanderen\.be\/ns\/besluit#(Agendapunt|Besluit|Bestuursorgaan|BehandelingVanAgendapunt|Zitting|Stemming)$/;
export default [
  {
    match: {
      predicate: {
        type: 'uri',
        value: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
      },
      object: {
        type: 'uri',
        value: interestingTypes
      }
    },
    callback: {
      url: 'http://uuid-generation/delta',
      method: 'POST'
    },
    options: {
      resourceFormat: 'v0.0.1',
      gracePeriod: 5000,
      sendMatchesOnly: true,
      foldEffectiveChanges: true
    }
  }
  {
    match: { },
    callback: {
      url: 'http://search/update',
      method: 'POST'
    },
    options: {
      resourceFormat: "v0.0.1",
      gracePeriod: 5000,
      foldEffectiveChanges: true
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
