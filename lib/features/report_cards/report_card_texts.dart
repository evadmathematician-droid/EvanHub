/// Fixed wording printed on every report card cover page. Edit here; the PDF
/// builder only lays these out.
class ReportCardTexts {
  ReportCardTexts._();

  // --- Left panel, top box (key) -------------------------------------------

  static const keyLine = 'Key: Mn = Average; Pos = Position';

  static const affectiveHeading = 'Affective.';
  static const affective = [
    '1 = Class participation; 2 = Sociability; 3 = Helpfulness 4 = Honesty',
    '5 = Effort; 6 = Initiative; 7 = Self-discipline 8 = Demeanor;',
    '9 = Sportsmanship; 10 = Dependability/ Reliability',
    '11 = Punctuality/ Regularity; 12 = School and Community Involvement;',
    '13 = Neatness',
  ];

  static const psychomotorHeading = 'Psychomotor.';
  static const psychomotorNote = ' (A minimum of 6 Aspects to be assessed)';
  static const psychomotor = [
    '1 = Physical dexterity; 2 = Stamina 3 = Physical Agility;',
    '4 = Individual Sporting prowess in ball games;',
    '5 = Ability to function as a team player in ball games;',
    '6 = Sport prowess in Athletic',
    '7 = Drawing and painting (artistic) skill;',
    '8 = Handwriting; 9 = Physical Co-ordination (in dance);',
    '10 = Voice control in talking and singing;',
    '11 = Musical instrument playing skill;',
    '12 = Bodily control/ sense of balance.',
  ];

  static const cognitiveHeading = 'Cognitive:';
  static const cognitiveNote = ' Marks/Scores.';
  static const cognitive = [
    'Mean = Reasonable but needs to set goals higher',
    'Above Mean = Reasonable but must maintain effect',
    'Below Mean = Improvement needed; Discuss with teacher',
  ];

  static const ratings =
      'Affective and Psychomotor Ratings 4 = Good/Often 5 = Great/Excellent '
      'exceptional/ Always too Little/ Rarely/ Poor 3 = Some/ Sometimes/ '
      'fair/ Reasonable / 1 = Negligible/ Never/ Very little/ Very Poor.';

  // --- Left panel, bottom box (notice) -------------------------------------

  static const noticeHeading = 'NOTICE TO PARENTS/GUARDIANS';
  static const notice = [
    'This Card report on the whole pupil not just the academic or cognitive.',
    'Look at it carefully and discuss what you do not understand with the '
        'teacher. Find out from the school how you can help the school and '
        'your child, try and work together with the school to get the most '
        'and the best out of your child when he/she is at home. Try and '
        'discourage your child from being absent, gambling, using drugs, '
        'cigarettes and alcohol. Encourage your child to be honest and '
        'truthful, hardworking, tidy, considerate of others and disciplined.',
  ];

  // --- Middle panel ----------------------------------------------------------

  static const pointsHeading = 'IMPORTANT POINTS TO NOTE.';
  static const points = [
    '10 unexcused absences will lead to an expulsion of pupil from the school.',
    'School funds should be paid during the first week of opening of each '
        'term.',
    'Pupils must comply with the uniform /dress code regulations for '
        'admission in the school at all time.',
    'Parent/guardian must sign and return report Cards throughout the year.',
    'A grade in red means below average of that class in the particular '
        'subject.',
    'Parent/guardian must endeavor to secure prescribed text-books for their '
        'children/wards.',
  ];

  // --- Right panel -----------------------------------------------------------

  static const juniorLevelLine = 'JUNIOR SECONDARY SCHOOL';
  static const seniorLevelLine = 'SENIOR SECONDARY SCHOOL';
  static const mottoLabel = 'Motto: ';
  static const foundedLabel = 'Founded: ';
  static const assessmentLine = 'CONTINUOUS ASSESSMENT';
  static const reportCardLine = 'REPORT CARD';
  static const pupilNameLabel = 'Name of Pupil: ';
  static const admissionLabel = 'Admission Number: ';
  static const formLabel = 'Form: ';
  static const principalLabel = 'Principal.';

  /// Printed where a value is missing.
  static const dots = '……………';
}
